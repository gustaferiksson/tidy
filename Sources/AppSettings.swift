import Foundation
import Observation
import TidyCore

enum MenuBarStyle: String, CaseIterable {
    case iconAndCount, countOnly, iconOnly
}

enum MenuBarCount: String {
    case unread, notDone
}

enum SettingsTab: String {
    case general, github, notifications, filters, keyboard, about
}

@MainActor @Observable
final class AppSettings {
    static let shared: AppSettings = {
        #if DEBUG
        if SettingsSnapshot.output != nil {
            let suite = "dev.gustaf.Tidy.snapshot"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return AppSettings(store: UserDefaults(suiteName: suite) ?? .standard)
        }
        #endif
        return AppSettings(store: .standard)
    }()

    @ObservationIgnored private let store: UserDefaults

    var showMenuBarIcon: Bool { didSet { store.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    var menuBarStyle: MenuBarStyle { didSet { store.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    var menuBarCount: MenuBarCount { didSet { store.set(menuBarCount.rawValue, forKey: "menuBarCount") } }
    var checksForUpdatesAutomatically: Bool { didSet { store.set(checksForUpdatesAutomatically, forKey: "checksForUpdatesAutomatically") } }
    var settingsTab: SettingsTab { didSet { store.set(settingsTab.rawValue, forKey: "settingsTab") } }
    var shortcuts: ShortcutBindings { didSet { store.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") } }

    init(store: UserDefaults) {
        store.register(defaults: ["showMenuBarIcon": true, "checksForUpdatesAutomatically": true])
        self.store = store
        showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
        menuBarStyle = store.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init) ?? .iconAndCount
        menuBarCount = store.string(forKey: "menuBarCount").flatMap(MenuBarCount.init) ?? .unread
        checksForUpdatesAutomatically = store.bool(forKey: "checksForUpdatesAutomatically")
        settingsTab = store.string(forKey: "settingsTab").flatMap(SettingsTab.init) ?? .general
        shortcuts = store.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode(ShortcutBindings.self, from: $0) } ?? .defaults
    }
}
