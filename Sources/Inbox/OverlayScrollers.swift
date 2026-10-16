import AppKit
import SwiftUI

struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ScrollerStyleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ScrollerStyleView: NSView {
        private weak var scrollView: NSScrollView?
        private var styleObservation: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let center = NotificationCenter.default
            observers = [
                // AppKit resets every scroll view to the preferred style when the system setting or mouse changes.
                center.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyOverlay() }
                },
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyOverlay() }
                },
            ]
            applyOverlay()
        }

        override func layout() {
            super.layout()
            applyOverlay()
        }

        private func applyOverlay() {
            guard let scrollView = scrollView ?? findScrollView() else { return }
            if scrollView !== self.scrollView {
                self.scrollView = scrollView
                styleObservation = scrollView.observe(\.scrollerStyle) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.applyOverlay() }
                }
            }
            scrollView.autohidesScrollers = true
            guard scrollView.scrollerStyle != .overlay else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.tile()
        }

        private func findScrollView() -> NSScrollView? {
            if let enclosingScrollView { return enclosingScrollView }
            guard let root = window?.contentView, !bounds.isEmpty else { return nil }
            let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: nil)
            return scrollViews(in: root)
                .filter { $0.convert($0.bounds, to: nil).contains(center) }
                .min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        }

        private func scrollViews(in view: NSView) -> [NSScrollView] {
            let nested = view.subviews.flatMap(scrollViews)
            guard let scrollView = view as? NSScrollView else { return nested }
            return [scrollView] + nested
        }
    }
}
