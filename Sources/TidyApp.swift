import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $settings.showMenuBarIcon) {
            InboxWindow(updater: appDelegate.updater)
                .environment(appDelegate.store)
        } label: {
            Image(systemName: "tray")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
                .environment(appDelegate.updater)
                .environment(appDelegate.store)
        }
    }
}

private struct InboxWindow: View {
    let updater: AppUpdater

    var body: some View {
        VStack(spacing: 0) {
            ContentUnavailableView("Inbox coming soon", systemImage: "tray")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                UpdateButton(updater: updater)
                Spacer()
                SettingsLink { Text("Settings…") }
                    .keyboardShortcut(",")
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 360, height: 480)
    }
}

private struct UpdateButton: View {
    let updater: AppUpdater

    var body: some View {
        if let staged = updater.staged {
            Button("Install \(staged.version) and Relaunch", action: updater.installAndRelaunch)
        } else {
            Button(checkTitle) { updater.check(.manual) }
                .disabled(updater.isBusy)
                .help(note ?? "")
        }
    }

    private var checkTitle: String {
        if updater.status == .checking { return "Checking…" }
        if updater.status == .downloading { return "Downloading…" }
        return "Check for Updates…"
    }

    private var note: String? {
        if case .upToDate(let version) = updater.status { return "Tidy \(version) is the latest version." }
        if case .blocked(let message) = updater.status { return message }
        if case .failed(let message) = updater.status { return message }
        return nil
    }
}
