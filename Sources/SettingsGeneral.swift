import ServiceManagement
import SwiftUI
import TidyCore

struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    @Environment(AppUpdater.self) private var updater
    @Environment(InboxStore.self) private var store
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
                        let title = switch style {
                        case .iconAndCount: "Icon and Count"
                        case .countOnly: "Count Only"
                        case .iconOnly: "Icon Only"
                        }
                        SketchOption(value: style, title: title, selection: $settings.menuBarStyle) {
                            HStack(spacing: 4) {
                                if style != .countOnly { Image(systemName: style == .iconOnly ? "tray.badge" : "tray") }
                                if style != .iconOnly { Text("3").monospacedDigit() }
                            }
                            .font(.system(size: 13, weight: .medium))
                        }
                    }
                }
                .padding(.vertical, 4)
                .disabled(!settings.showMenuBarIcon)
                Picker("Menu bar shows", selection: $settings.menuBarCount) {
                    Text("Unread notifications").tag(MenuBarCount.unread)
                    Text("Everything not done").tag(MenuBarCount.notDone)
                    if !store.metrics.isEmpty { Divider() }
                    ForEach(store.metrics) { metric in
                        Text(metric.title).tag(MenuBarCount.metric(metric.id))
                    }
                }
                .disabled(!settings.showMenuBarIcon)
                .onChange(of: settings.menuBarCount) { _, count in store.menuBarMetric = count.metricID }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("When hidden, open Tidy again to show Settings.")
            }

            Section {
                Picker("Return to the list after", selection: $settings.returnToListAfter) {
                    Text("1 minute").tag(ReturnToListDelay.oneMinute)
                    Text("5 minutes").tag(ReturnToListDelay.fiveMinutes)
                    Text("15 minutes").tag(ReturnToListDelay.fifteenMinutes)
                    Text("1 hour").tag(ReturnToListDelay.oneHour)
                    Text("Never").tag(ReturnToListDelay.never)
                }
            } header: {
                Text("Inbox")
            } footer: {
                Text("When Tidy was left open on a conversation, reopening it after this long shows the list.")
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $settings.checksForUpdatesAutomatically)
                    .onChange(of: settings.checksForUpdatesAutomatically) { _, isOn in
                        if isOn { updater.scheduleChecks() } else { updater.stopScheduledChecks() }
                    }
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
        .frame(height: 560)
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
