import SwiftUI
import TidyCore

struct FilterSettings: View {
    @Environment(InboxStore.self) private var store
    @State private var selection = Set<UUID>()
    @State private var editing: FilterRule?
    @State private var unmuting = Set<String>()
    @State private var unmuteError: String?

    var body: some View {
        Form {
            Section {
                List(selection: $selection) {
                    ForEach(store.rules) { rule in
                        RuleRow(rule: rule)
                    }
                    .onMove { store.rules.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 176)
                .overlay {
                    if store.rules.isEmpty {
                        Text("No Rules")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onDeleteCommand(perform: removeSelected)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Edit…") { editing = store.rules.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Delete", role: .destructive) {
                        store.rules.removeAll { ids.contains($0.id) }
                        selection.subtract(ids)
                    }
                } primaryAction: { ids in
                    editing = store.rules.first { ids.contains($0.id) }
                }
                HStack(spacing: 4) {
                    Button("Add Rule…", systemImage: "plus") { editing = FilterRule(conditions: [.repository("")]) }
                        .labelStyle(.iconOnly)
                    Button("Remove", systemImage: "minus", action: removeSelected)
                        .labelStyle(.iconOnly)
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button("Edit…") { editing = store.rules.first { selection.contains($0.id) } }
                        .disabled(selection.count != 1)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules run from the top and the first match wins. Drag to reorder.")
            }

            Section {
                if store.muted.isEmpty {
                    Text("Threads you mute from the inbox appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.muted) { thread in
                    LabeledContent {
                        Button("Unmute") { unmute(thread.id) }
                            .disabled(unmuting.contains(thread.id))
                    } label: {
                        Text(thread.title)
                            .lineLimit(1)
                        Text(thread.repository)
                    }
                }
            } header: {
                Text("Muted Threads")
            } footer: {
                if let unmuteError {
                    Text(unmuteError)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 520)
        .sheet(item: $editing) { rule in
            let index = store.rules.firstIndex { $0.id == rule.id }
            RuleEditor(rule: rule, isNew: index == nil, repositories: store.repositories) { saved in
                guard let index else { return store.rules.append(saved) }
                store.rules[index] = saved
            } onDelete: {
                store.rules.removeAll { $0.id == rule.id }
                selection.remove(rule.id)
            }
        }
        #if DEBUG
        .onAppear {
            guard SettingsSnapshot.scene == "ruleEditor" else { return }
            editing = store.rules.last
        }
        #endif
    }

    private func removeSelected() {
        store.rules.removeAll { selection.contains($0.id) }
        selection = []
    }

    private func unmute(_ id: String) {
        unmuting.insert(id)
        unmuteError = nil
        Task {
            defer { unmuting.remove(id) }
            do {
                try await store.unmute(id)
            } catch {
                unmuteError = (error as? GitHubError)?.message ?? "Couldn't unmute the thread."
            }
        }
    }
}

private struct RuleRow: View {
    let rule: FilterRule

    var body: some View {
        let summary = rule.conditions.map { condition in
            switch condition {
            case .repository(let name): "Repository is \(name)"
            case .notRepository(let name): "Repository is not \(name)"
            case .reason(let reason): "Reason is \(reason.title)"
            case .category(let category): "Type is \(category.title)"
            case .author(let login): "Author is \(login)"
            case .state(let state): "State is \(state.title)"
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.joined(separator: " and "))
                .lineLimit(2)
            Text(rule.action.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
