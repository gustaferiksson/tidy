import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        TabView(selection: $settings.settingsTab) {
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
        .onAppear {
            #if DEBUG
            guard SettingsSnapshot.output == nil else { return }
            #endif
            NSApp.activate()
        }
    }
}
