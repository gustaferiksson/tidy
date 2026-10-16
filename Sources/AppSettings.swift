import Foundation
import Observation

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

    init(store: UserDefaults) {
        store.register(defaults: ["showMenuBarIcon": true])
        self.store = store
        showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
    }
}
