import SwiftUI
import TidyCore

enum SettingsTab: String {
    case general, github, notifications, filters, about
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(InboxStore.self) private var store
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettings(settings: settings)
            }
            Tab("GitHub", systemImage: "person.crop.circle", value: .github) {
                GitHubSettings()
            }
            Tab("Notifications", systemImage: "bell.badge", value: .notifications) {
                NotificationSettings()
            }
            Tab("Filters", systemImage: "line.3.horizontal.decrease.circle", value: .filters) {
                FilterSettings()
            }
            Tab("About", systemImage: "info.circle", value: .about) {
                AboutSettings()
            }
        }
        .frame(width: 560)
        .environment(snapshotStore ?? store)
        .onAppear { NSApp.activate() }
    }

    private var snapshotStore: InboxStore? {
        #if DEBUG
        SettingsSnapshot.store
        #else
        nil
        #endif
    }
}
