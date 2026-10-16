import Foundation
import Observation

enum MenuBarStyle: String, CaseIterable {
    case iconAndCount, countOnly, iconOnly
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

    init(store: UserDefaults) {
        store.register(defaults: ["showMenuBarIcon": true])
        self.store = store
        showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
        menuBarStyle = store.string(forKey: "menuBarStyle").flatMap(MenuBarStyle.init) ?? .iconAndCount
    }
}
