import AppKit
import SwiftUI
import TidyCore

@MainActor
@Observable
final class PanelController {
    private(set) var isOpen = false
    var quickLookID: String?
    var selection: Set<String> = []

    @ObservationIgnored private let store: InboxStore
    @ObservationIgnored private let updater: AppUpdater
    @ObservationIgnored private var previousApp: NSRunningApplication?
    @ObservationIgnored private var activationObserver: NSObjectProtocol?
    @ObservationIgnored private var fallbackWindow: NSWindow?

    init(store: InboxStore, updater: AppUpdater) {
        self.store = store
        self.updater = updater
        previousApp = NSWorkspace.shared.frontmostApplication.flatMap { $0 == .current ? nil : $0 }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
    }

    func panelDidOpen() {
        isOpen = true
    }

    func panelDidClose() {
        guard isOpen else { return }
        isOpen = false
        Task { await store.flushPending() }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !isOpen, NSApp.keyWindow == nil, NSWorkspace.shared.frontmostApplication == .current else { return }
            previousApp?.activate()
        }
    }

    func open(quickLook id: String? = nil) {
        if let id {
            selection = [id]
            quickLookID = id
        }
        guard !isOpen else { return }
        NSApp.activate()
        let button = NSApp.windows
            .filter { $0.className.contains("NSStatusBarWindow") }
            .compactMap { $0.contentView?.firstSubview(ofType: NSStatusBarButton.self) }
            .first
        guard let button else {
            showFallbackWindow()
            return
        }
        button.performClick(nil)
    }

    private func showFallbackWindow() {
        let window = fallbackWindow ?? Self.makePanelWindow(
            content: InboxPanel().environment(store).environment(self).environment(updater)
        )
        fallbackWindow = window
        if let screen = NSScreen.main?.visibleFrame {
            window.setFrameTopLeftPoint(NSPoint(x: screen.maxX - window.frame.width - 12, y: screen.maxY - 4))
        }
        window.makeKeyAndOrderFront(nil)
    }

    static func makePanelWindow(content: some View) -> NSWindow {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: InboxPanel.size.width, height: InboxPanel.size.height),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.contentView = NSHostingView(rootView: content)
        return window
    }
}

private extension NSView {
    func firstSubview<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        return subviews.lazy.compactMap { $0.firstSubview(ofType: type) }.first
    }
}

struct PanelWindowObserver: NSViewRepresentable {
    let panel: PanelController

    func makeNSView(context: Context) -> NSView {
        WindowTrackingView(panel: panel)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowTrackingView: NSView {
        let panel: PanelController
        private var observers: [NSObjectProtocol] = []

        init(panel: PanelController) {
            self.panel = panel
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            guard let window else {
                observers = []
                return
            }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [panel] _ in
                    MainActor.assumeIsolated { panel.panelDidOpen() }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [panel] _ in
                    MainActor.assumeIsolated { panel.panelDidClose() }
                },
            ]
            if window.isKeyWindow { panel.panelDidOpen() }
        }
    }
}
