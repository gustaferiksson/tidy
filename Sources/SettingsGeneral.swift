import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    @Environment(AppUpdater.self) private var updater
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                    set: setLaunchAtLogin
                ))
                if loginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("Approval needed")
                        Text("Allow Tidy in System Settings to finish turning this on.")
                    }
                }
                if let loginError {
                    Text(loginError)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                HStack(spacing: 12) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        MenuBarStyleOption(style: style, selection: $settings.menuBarStyle)
                    }
                }
                .padding(.vertical, 4)
                .disabled(!settings.showMenuBarIcon)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("When hidden, open Tidy again to show Settings.")
            }

            Section("Updates") {
                HStack(spacing: 8) {
                    updateStatus
                    Spacer()
                    if updater.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(updater.status == .checking ? "Checking" : "Downloading")
                    }
                    if let staged = updater.staged {
                        Button("Install Tidy \(staged.version) and Relaunch", action: updater.installAndRelaunch)
                    } else {
                        Button("Check for Updates") { updater.check(.manual) }
                            .disabled(updater.isBusy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 420)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    @ViewBuilder private var updateStatus: some View {
        if updater.status == .checking {
            Text("Checking for updates…").font(.callout).foregroundStyle(.secondary)
        } else if updater.status == .downloading {
            Text("Downloading the update…").font(.callout).foregroundStyle(.secondary)
        } else if case .upToDate(let version) = updater.status {
            Text("Tidy \(version) is the latest version.").font(.callout).foregroundStyle(.secondary)
        } else if case .ready(let version) = updater.status {
            Text("Tidy \(version) is ready to install.").font(.callout)
        } else if case .blocked(let message) = updater.status {
            Text(message).font(.callout).foregroundStyle(.orange)
        } else if case .failed(let message) = updater.status {
            Text(message).font(.callout).foregroundStyle(.red)
        } else {
            Text("Version \(AppUpdater.currentVersion)").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func setLaunchAtLogin(_ isOn: Bool) {
        do {
            if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change Launch at login: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}

private struct MenuBarStyleOption: View {
    let style: MenuBarStyle
    @Binding var selection: MenuBarStyle
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isSelected = selection == style
        let title = switch style {
        case .iconAndCount: "Icon and Unread Count"
        case .countOnly: "Unread Count Only"
        case .iconOnly: "Icon Only"
        }
        Button { selection = style } label: {
            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    if style != .countOnly { Image(systemName: "tray.badge") }
                    if style != .iconOnly { Text("3").monospacedDigit() }
                }
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
