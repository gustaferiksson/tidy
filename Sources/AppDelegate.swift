import AppKit
import TidyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updater = AppUpdater()
    let store: InboxStore
    let panel: PanelController
    private let banners: Banners
    private var sleepObservers: [NSObjectProtocol] = []

    override init() {
        #if DEBUG
        store = SettingsSnapshot.store ?? (InboxSnapshot.output == nil ? InboxStore() : InboxSnapshot.makeStore(.populated))
        #else
        store = InboxStore()
        #endif
        panel = PanelController(store: store, updater: updater)
        banners = Banners(store: store, panel: panel)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        guard SettingsSnapshot.output == nil, InboxSnapshot.output == nil else { return }
        #endif
        banners.start()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let output = SettingsSnapshot.output {
            Task { await SettingsSnapshot.capture(to: output) }
            return
        }
        if let output = InboxSnapshot.output {
            Task { await InboxSnapshot.capture(to: output, updater: updater) }
            return
        }
        #endif
        updater.start()
        store.start()
        let workspace = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [store] _ in
                MainActor.assumeIsolated { store.pause() }
            },
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [store] _ in
                MainActor.assumeIsolated { store.resume() }
            },
        ]
    }

    func applicationWillTerminate(_ notification: Notification) {
        updater.installOnQuit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if AppSettings.shared.showMenuBarIcon { panel.open() } else { panel.showSettings() }
        return true
    }
}
