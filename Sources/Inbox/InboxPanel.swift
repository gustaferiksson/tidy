import SwiftUI
import TidyCore

struct InboxPanel: View {
    static let size = CGSize(width: 400, height: 560)

    @Environment(InboxStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Environment(AppUpdater.self) private var updater
    @Environment(\.openSettings) private var openSettings
    @AppStorage("showsAllThreads") private var showsAll = false

    var body: some View {
        @Bindable var panel = panel
        NavigationStack {
            VStack(spacing: 0) {
                header
                if store.scope.isActive { filterChips }
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.isSignedIn {
                    Divider()
                    footer
                }
            }
            .navigationDestination(item: $panel.quickLookID) { id in
                QuickLookView(id: id, order: items)
            }
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: Self.size.width, height: Self.size.height)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .containerBackground(.clear, for: .window)
        .environment(\.openURL, OpenURLAction { $0.isGitHubWeb ? .systemAction : .discarded })
        .background { shortcuts }
        .background(PanelWindowObserver(panel: panel))
        .onExitCommand {
            if panel.quickLookID != nil {
                panel.quickLookID = nil
            } else {
                NSApp.keyWindow?.close()
            }
        }
    }

    private var items: [InboxItem] {
        showsAll ? store.visibleItems : store.visibleItems.filter { $0.isUnread || $0.id == panel.quickLookID || panel.openedIDs.contains($0.id) }
    }

    private var header: some View {
        HStack(spacing: 4) {
            if store.isSignedIn {
                Picker("Show", selection: $showsAll) {
                    Text("Unread").tag(false)
                    Text("All").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .focusEffectDisabled()
            }
            Spacer(minLength: 8)
            if store.isSignedIn { filterMenu }
            moreMenu
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .frame(height: 44)
    }

    @ViewBuilder private var filterMenu: some View {
        @Bindable var store = store
        Menu {
            Toggle("Participating Only", isOn: $store.scope.participatingOnly)
            Picker("Repository", selection: $store.scope.repository) {
                Text("All Repositories").tag(String?.none)
                Divider()
                ForEach(store.repositories, id: \.self) { Text($0).tag(Optional($0)) }
            }
            .pickerStyle(.menu)
            .disabled(store.repositories.isEmpty)
        } label: {
            Image(systemName: store.scope.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
        }
        .fixedSize()
        .help("Filter")
        .accessibilityLabel("Filter")
    }

    private var moreMenu: some View {
        Menu {
            if store.isSignedIn {
                Button("Mark All as Read", action: store.markAllRead)
                    .disabled(store.unreadCount == 0)
                Divider()
            }
            if let staged = updater.staged {
                Button("Install \(staged.version) and Relaunch", action: updater.installAndRelaunch)
            } else {
                Button(updater.status == .checking ? "Checking for Updates…" : "Check for Updates…") { updater.check(.manual) }
                    .disabled(updater.isBusy)
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Tidy") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis.circle")
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .frame(width: 28, height: 28)
        }
        .fixedSize()
        .help("More")
        .accessibilityLabel("More")
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            if store.scope.participatingOnly {
                FilterChip(title: "Participating") { store.scope.participatingOnly = false }
            }
            if let repository = store.scope.repository {
                FilterChip(title: repository) { store.scope.repository = nil }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var content: some View {
        if !store.isSignedIn {
            ContentUnavailableView {
                Label("Connect GitHub", systemImage: "tray")
            } description: {
                Text("Tidy reads your notifications with a personal access token (classic).")
            } actions: {
                Button("Connect…") {
                    AppSettings.shared.settingsTab = .github
                    openSettings()
                }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.issue == .unauthorized {
            ContentUnavailableView {
                Label("Your GitHub token is no longer valid", systemImage: "exclamationmark.triangle")
            } actions: {
                Button("Update Token…") {
                    AppSettings.shared.settingsTab = .github
                    openSettings()
                }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.issue == .missingScope {
            ContentUnavailableView {
                Label("Token needs the repo scope", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Create a classic token with the notifications and repo scopes, then replace it in Settings.")
            } actions: {
                Link("Create Token…", destination: URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo&description=Tidy")!)
                    .buttonStyle(.borderedProminent)
            }
        } else if !store.hasLoaded && store.issue == .offline {
            ContentUnavailableView {
                Label("Can't reach GitHub", systemImage: "wifi.slash")
            } actions: {
                Button("Retry", action: store.pollNow)
            }
        } else if !store.hasLoaded && store.issue == .keychainUnavailable {
            ContentUnavailableView {
                Label("Can't read your token from the Keychain", systemImage: "key.slash")
            } actions: {
                Button("Retry", action: store.pollNow)
            }
        } else if !store.hasLoaded {
            ProgressView()
        } else {
            InboxList(items: items, showsAll: showsAll)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            footerStatus
            Spacer(minLength: 8)
            if let staged = updater.staged {
                Button("Install \(staged.version)", action: updater.installAndRelaunch)
                    .buttonStyle(.link)
            }
            if showsRefresh { refreshButton }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .frame(height: 28)
    }

    private var showsRefresh: Bool {
        let showsRetry = store.failure == nil && store.undoableChange == nil && (store.issue == .keychainUnavailable || store.issue == .notResponding)
        return store.hasLoaded && !showsRetry && store.issue != .unauthorized && store.issue != .missingScope
    }

    private var refreshButton: some View {
        ZStack {
            ProgressView().controlSize(.mini).opacity(store.isRefreshing ? 1 : 0)
            Button(action: store.pollNow) {
                Image(systemName: "arrow.clockwise").imageScale(.small)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .pointerStyle(.link)
            .disabled(store.isRefreshing)
            .opacity(store.isRefreshing ? 0 : 1)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
    }

    @ViewBuilder private var footerStatus: some View {
        if let failure = store.failure {
            Text(failure.message)
            Button("Retry", action: store.retryFailed).buttonStyle(.link)
        } else if let change = store.undoableChange {
            Text(change.items.count == 1 ? change.message.replacingOccurrences(of: " 1 ", with: " ") : change.message)
            Button("Undo", action: undo)
                .buttonStyle(.link)
                .keyboardShortcut("z", modifiers: .command)
        } else if store.issue == .offline {
            Label(store.lastSync.map { "Offline · updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Offline", systemImage: "wifi.slash")
        } else if case .rateLimited(let resumesAt) = store.issue {
            Text("GitHub rate limit · resumes \(resumesAt.formatted(date: .omitted, time: .shortened))")
        } else if case .ssoRequired(let organization, let url) = store.issue {
            let title = "Authorize token for \(organization ?? "your organization")"
            if let url { Link(title, destination: url) } else { Text(title) }
        } else if store.issue == .keychainUnavailable {
            Text("Can't read your token from the Keychain")
            Button("Retry", action: store.pollNow).buttonStyle(.link)
        } else if store.issue == .notResponding {
            Text("GitHub isn't responding")
            Button("Retry", action: store.pollNow).buttonStyle(.link)
        } else if store.hiddenCount > 0 && store.hasLoaded {
            Text(store.showsHidden ? "Showing \(store.hiddenCount) hidden by filters" : "\(store.hiddenCount) hidden by filters")
            Button(store.showsHidden ? "Hide" : "Show") { store.showsHidden.toggle() }.buttonStyle(.link)
        } else if store.isCapped {
            Text("Showing the last 14 days")
        } else if let lastSync = store.lastSync {
            TimelineView(.everyMinute) { context in
                let age = shortAge(of: lastSync, now: context.date)
                Text(age == "now" ? "Updated just now" : "Updated \(age) ago")
            }
        }
    }

    private func undo() {
        let ids = store.undo()
        panel.selection = Set(ids)
        panel.revealID = ids.first
    }

    private var shortcuts: some View {
        ZStack {
            Button("Unread") { showsAll = false }.keyboardShortcut("1")
            Button("All") { showsAll = true }.keyboardShortcut("2")
            Button("Select All") { panel.selection = Set(items.map(\.id)) }
                .keyboardShortcut("a")
                .disabled(panel.quickLookID != nil)
            Button("Mark All as Read", action: store.markAllRead).keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Refresh", action: store.pollNow)
                .keyboardShortcut("r")
                .disabled(!store.isSignedIn || store.isRefreshing)
            SettingsLink { Text("Settings…") }.keyboardShortcut(",")
            Button("Quit Tidy") { NSApp.terminate(nil) }.keyboardShortcut("q")
            Button("Back") { panel.quickLookID = nil }.keyboardShortcut("[")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

private struct FilterChip: View {
    let title: String
    let clear: () -> Void

    var body: some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .help("Remove Filter")
    }
}
