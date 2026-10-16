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
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("When hidden, open Tidy again to show Settings.")
            }

            Section("Updates") {
                LabeledContent("Version", value: AppUpdater.currentVersion)
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
        .frame(height: 360)
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
