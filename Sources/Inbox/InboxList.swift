import AppKit
import SwiftUI
import TidyCore

struct InboxList: View {
    let items: [InboxItem]
    let showsAll: Bool
    @Environment(InboxStore.self) private var store
    @Environment(PanelController.self) private var panel
    @AppStorage("doneExpanded") private var doneExpanded = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if items.isEmpty && store.done.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list
                }
            }
            .overlay(alignment: .bottom) { toast(proxy: proxy) }
            .animation(.snappy, value: store.undoableChange?.id)
        }
        .onAppear { isFocused = true }
        .onChange(of: panel.isOpen) { if panel.isOpen { isFocused = true } }
    }

    private var list: some View {
        @Bindable var panel = panel
        return TimelineView(.everyMinute) { context in
            List(selection: $panel.selection) {
                if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .frame(height: doneExpanded ? 240 : 400)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                }
                ForEach(items) { item in
                    InboxRow(item: item, isDone: false, now: context.date)
                        .listRowInsets(EdgeInsets())
                }
                if !store.done.isEmpty {
                    doneHeader
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                    if doneExpanded {
                        ForEach(store.done) { item in
                            InboxRow(item: item, isDone: true, now: context.date)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { ids in contextMenu(for: ids) }
            .focused($isFocused)
            .onKeyPress(.space) {
                guard let id = selected.first?.id else { return .ignored }
                panel.quickLookID = id
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                guard !selected.isEmpty else { return .ignored }
                for item in selected { NSWorkspace.shared.open(item.webURL) }
                if !press.modifiers.contains(.option) { store.markRead(selected.map(\.id)) }
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "eEI")) { press in
                guard !selected.isEmpty, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
                if press.characters == "I" {
                    store.markRead(selected.map(\.id))
                } else {
                    markDoneOrRestore(selected)
                }
                return .handled
            }
        }
    }

    private var selected: [InboxItem] {
        (items + store.done).filter { panel.selection.contains($0.id) }
    }

    private var doneHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.snappy) { doneExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(doneExpanded ? 90 : 0))
                        .frame(width: 12)
                    Text("Done · \(store.done.count)")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityValue(doneExpanded ? "Expanded" : "Collapsed")
            Button("Remove All", action: store.removeAllDone)
                .buttonStyle(.borderless)
                .font(.subheadline)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(height: 36)
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

    @ViewBuilder private func toast(proxy: ScrollViewProxy) -> some View {
        if let change = store.undoableChange {
            HStack(spacing: 8) {
                Text(change.message)
                Button("Undo") { undo(proxy: proxy) }
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
                    .keyboardShortcut("z", modifiers: .command)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func undo(proxy: ScrollViewProxy) {
        let ids = store.undo()
        panel.selection = Set(ids)
        guard let first = ids.first else { return }
        if store.done.contains(where: { $0.id == first }) { doneExpanded = true }
        withAnimation { proxy.scrollTo(first) }
    }

    private func markDoneOrRestore(_ targets: [InboxItem]) {
        let doneIDs = Set(store.done.map(\.id))
        let ordered = items + (doneExpanded ? store.done : [])
        let lastIndex = ordered.lastIndex { panel.selection.contains($0.id) }
        let next = lastIndex.flatMap { ordered[($0 + 1)...].first { !panel.selection.contains($0.id) } }
        store.markDone(targets.filter { !doneIDs.contains($0.id) }.map(\.id))
        store.moveToInbox(targets.filter { doneIDs.contains($0.id) }.map(\.id))
        panel.selection = next.map { [$0.id] } ?? []
    }

    @ViewBuilder private func contextMenu(for ids: Set<String>) -> some View {
        let targets = (items + store.done).filter { ids.contains($0.id) }
        let doneIDs = Set(store.done.map(\.id))
        if !targets.isEmpty {
            Button("Quick Look") { panel.quickLookID = targets.first?.id }
                .disabled(targets.count != 1)
            Button("Open on GitHub") {
                for item in targets { NSWorkspace.shared.open(item.webURL) }
                store.markRead(targets.map(\.id))
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(targets.map(\.webURL.absoluteString).joined(separator: "\n"), forType: .string)
            }
            Divider()
            Button("Mark as Read") { store.markRead(targets.map(\.id)) }
                .disabled(!targets.contains(where: \.isUnread))
            if targets.allSatisfy({ doneIDs.contains($0.id) }) {
                Button("Move to Inbox") { store.moveToInbox(targets.map(\.id)) }
            } else {
                Button("Done") { store.markDone(targets.map(\.id)) }
            }
            Divider()
            Button("Mute Thread") {
                for item in targets where !doneIDs.contains(item.id) { store.muteThread(item.id) }
            }
            .disabled(targets.allSatisfy { doneIDs.contains($0.id) })
            Button("Mute Repository") {
                for repository in Set(targets.map(\.thread.repository.fullName)) { store.muteRepository(repository) }
            }
        }
    }
}
