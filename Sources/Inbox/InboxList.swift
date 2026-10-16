import AppKit
import SwiftUI
import TidyCore

struct InboxList: View {
    private static let openLimit = 10

    let items: [InboxItem]
    let showsAll: Bool
    @Environment(InboxStore.self) private var store
    @Environment(PanelController.self) private var panel
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                if items.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .onChange(of: panel.revealID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id) }
                panel.revealID = nil
            }
            .focusable(interactions: .edit)
            .focusEffectDisabled()
            .focused($isFocused)
            .task(id: panel.isOpen && panel.quickLookID == nil) {
                guard panel.isOpen, panel.quickLookID == nil else { return }
                // AppKit assigns the window's initial first responder after the view appears, overriding an immediate request.
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                isFocused = true
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard press.modifiers.isDisjoint(with: [.shift, .command, .control, .option]) else { return .ignored }
                let order = items.map(\.id)
                guard let next = steppedSelection(from: panel.selection, in: order, by: press.key == .upArrow ? -1 : 1) else { return .ignored }
                panel.selection = [next]
                proxy.scrollTo(next)
                return .handled
            }
            .onKeyPress(.space) {
                guard let id = selected.first?.id else { return .ignored }
                panel.quickLookID = id
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.isDisjoint(with: [.command, .shift, .control, .option]) {
                    guard selected.count == 1, let id = selected.first?.id else { return .ignored }
                    panel.showDetails(id)
                    return .handled
                }
                guard press.modifiers.contains(.command), !selected.isEmpty, selected.count <= Self.openLimit else { return .ignored }
                for item in selected where item.webURL.isGitHubWeb { NSWorkspace.shared.open(item.webURL) }
                if !press.modifiers.contains(.option) { store.markRead(selected.map(\.id)) }
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "eEI")) { press in
                guard !selected.isEmpty, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                if press.characters == "I" {
                    store.markRead(selected.map(\.id))
                } else {
                    markDone(selected)
                }
                return .handled
            }
        }
    }

    private var list: some View {
        @Bindable var panel = panel
        return TimelineView(.everyMinute) { context in
            List(selection: $panel.selection) {
                ForEach(items) { item in
                    InboxRow(item: item, now: context.date)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(OverlayScrollers())
            .contextMenu(forSelectionType: String.self) { ids in contextMenu(for: ids) }
        }
    }

    private var selected: [InboxItem] {
        items.filter { panel.selection.contains($0.id) }
    }

    @ViewBuilder private var emptyState: some View {
        if let repository = store.scope.repository {
            ContentUnavailableView {
                Label(showsAll ? "Nothing in \(repository)" : "No unread in \(repository)", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear Filter") { store.scope = InboxScope() }
            }
        } else if store.scope.participatingOnly {
            ContentUnavailableView {
                Label(showsAll ? "Nothing you're participating in" : "No unread you're participating in", systemImage: "line.3.horizontal.decrease.circle")
            } actions: {
                Button("Clear Filter") { store.scope = InboxScope() }
            }
        } else {
            ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle")
        }
    }

    private func markDone(_ targets: [InboxItem]) {
        let lastIndex = items.lastIndex { panel.selection.contains($0.id) }
        let next = lastIndex.flatMap { items[($0 + 1)...].first { !panel.selection.contains($0.id) } }
        store.markDone(targets.map(\.id))
        panel.selection = next.map { [$0.id] } ?? []
    }

    @ViewBuilder private func contextMenu(for ids: Set<String>) -> some View {
        let targets = items.filter { ids.contains($0.id) }
        if !targets.isEmpty {
            Button("Quick Look") { targets.first.map { panel.showDetails($0.id) } }
                .disabled(targets.count != 1)
            Button("Open on GitHub") {
                for item in targets where item.webURL.isGitHubWeb { NSWorkspace.shared.open(item.webURL) }
                store.markRead(targets.map(\.id))
            }
            .disabled(targets.count > Self.openLimit)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(targets.map(\.webURL.absoluteString).joined(separator: "\n"), forType: .string)
            }
            Divider()
            if targets.contains(where: \.isUnread) {
                Button("Mark as Read") { store.markRead(targets.map(\.id)) }
            }
            Button("Done") { store.markDone(targets.map(\.id)) }
            Divider()
            Button("Mute Thread") {
                for item in targets { store.muteThread(item.id) }
            }
            Button("Mute Repository") {
                for repository in Set(targets.map(\.thread.repository.fullName)) { store.muteRepository(repository) }
            }
        }
    }
}
