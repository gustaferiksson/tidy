import SwiftUI
import TidyCore

struct RuleEditor: View {
    let isNew: Bool
    let repositories: [String]
    let onSave: (FilterRule) -> Void
    let onDelete: () -> Void
    @State private var draft: FilterRule
    @Environment(\.dismiss) private var dismiss

    init(rule: FilterRule, isNew: Bool, repositories: [String], onSave: @escaping (FilterRule) -> Void, onDelete: @escaping () -> Void) {
        self.isNew = isNew
        self.repositories = repositories
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: rule)
    }

    var body: some View {
        let trimmed = draft.conditions.map { condition -> FilterCondition in
            switch condition {
            case .repository(let name): .repository(name.trimmingCharacters(in: .whitespaces))
            case .notRepository(let name): .notRepository(name.trimmingCharacters(in: .whitespaces))
            case .author(let login): .author(login.trimmingCharacters(in: .whitespaces))
            case .reason, .category, .state: condition
            }
        }
        let isValid = !trimmed.isEmpty && !trimmed.contains { [.repository(""), .notRepository(""), .author("")].contains($0) }
        VStack(spacing: 0) {
            Form {
                Section("If all of these conditions are met") {
                    ForEach(draft.conditions.indices, id: \.self) { index in
                        ConditionRow(condition: Binding(
                            get: { draft.conditions.indices.contains(index) ? draft.conditions[index] : .repository("") },
                            set: { if draft.conditions.indices.contains(index) { draft.conditions[index] = $0 } }
                        ), repositories: repositories, canRemove: draft.conditions.count > 1) {
                            draft.conditions.remove(at: index)
                        }
                    }
                    Button("Add Condition", systemImage: "plus") { draft.conditions.append(.repository("")) }
                        .buttonStyle(.borderless)
                }
                Section("Then") {
                    Picker("Action", selection: $draft.action) {
                        ForEach(RuleAction.allCases, id: \.self) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    if draft.action.isOptIn {
                        Label {
                            Text(draft.action == .hideAndMarkDone
                                ? "This removes matching threads from your GitHub inbox. It only acts on threads that arrive after you save the rule."
                                : "This marks matching threads as read on GitHub. It only acts on threads that arrive after you save the rule.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 8) {
                if !isNew {
                    Button("Delete Rule", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(FilterRule(id: draft.id, conditions: trimmed, action: draft.action, savedAt: .now))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
    }
}

private enum ConditionField: CaseIterable {
    case repository, notRepository, reason, category, author, state

    init(_ condition: FilterCondition) {
        switch condition {
        case .repository: self = .repository
        case .notRepository: self = .notRepository
        case .reason: self = .reason
        case .category: self = .category
        case .author: self = .author
        case .state: self = .state
        }
    }

    var title: String {
        switch self {
        case .repository: "Repository is"
        case .notRepository: "Repository is not"
        case .reason: "Reason is"
        case .category: "Type is"
        case .author: "Author is"
        case .state: "State is"
        }
    }

    var initialCondition: FilterCondition {
        switch self {
        case .repository: .repository("")
        case .notRepository: .notRepository("")
        case .reason: .reason(.reviewRequested)
        case .category: .category(.pullRequest)
        case .author: .author("")
        case .state: .state(.open)
        }
    }
}

private struct ConditionRow: View {
    @Binding var condition: FilterCondition
    let repositories: [String]
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        let field = ConditionField(condition)
        HStack(spacing: 8) {
            Picker("Condition", selection: Binding(
                get: { field },
                set: { if $0 != field { condition = $0.initialCondition } }
            )) {
                ForEach(ConditionField.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 168, alignment: .leading)
            value(for: field)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Remove Condition", systemImage: "minus.circle.fill", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(!canRemove)
        }
    }

    @ViewBuilder private func value(for field: ConditionField) -> some View {
        if case .reason(let reason) = condition {
            Picker("Reason", selection: Binding(get: { reason }, set: { condition = .reason($0) })) {
                ForEach(ReasonGroup.allCases, id: \.self) { group in
                    Section(group.title) {
                        ForEach(group.reasons, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            .labelsHidden()
        } else if case .category(let category) = condition {
            Picker("Type", selection: Binding(get: { category }, set: { condition = .category($0) })) {
                ForEach(SubjectCategory.allCases.filter { $0 != .other }, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
        } else if case .state(let state) = condition {
            Picker("State", selection: Binding(get: { state }, set: { condition = .state($0) })) {
                ForEach(SubjectState.filterable, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
        } else {
            let isAuthor = field == .author
            let owners = Set(repositories.compactMap { $0.split(separator: "/").first.map(String.init) }).sorted()
            let suggestions = isAuthor ? FilterCondition.authorPresets : owners + repositories
            let binding = $condition
            let setText: @Sendable (String) -> Void = { text in
                binding.wrappedValue = switch field {
                case .notRepository: .notRepository(text)
                case .author: .author(text)
                case .repository, .reason, .category, .state: .repository(text)
                }
            }
            HStack(spacing: 4) {
                TextField(isAuthor ? "Author" : "Repository", text: Binding(
                    get: {
                        switch condition {
                        case .repository(let text), .notRepository(let text), .author(let text): text
                        case .reason, .category, .state: ""
                        }
                    },
                    set: setText
                ), prompt: Text(isAuthor ? "login" : "owner/repo or owner"))
                .labelsHidden()
                Menu {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { setText(suggestion) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(suggestions.isEmpty)
                .help(isAuthor ? "Bot presets" : "Repositories in your inbox")
            }
        }
    }
}
