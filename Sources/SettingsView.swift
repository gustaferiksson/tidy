import SwiftUI

enum SettingsTab: String {
    case general, about
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @AppStorage("settingsTab") private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            Tab("General", systemImage: "gearshape", value: .general) {
                GeneralSettings(settings: settings)
            }
            Tab("About", systemImage: "info.circle", value: .about) {
                AboutSettings()
            }
        }
        .frame(width: 560)
        .onAppear { NSApp.activate() }
    }
}
