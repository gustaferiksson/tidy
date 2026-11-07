import SwiftUI
import TidyCore

struct MetricEditor: View {
    let onSave: (Metric) -> Void
    private let id: UUID
    @State private var title: String
    @State private var filter: String
    @State private var scope: ScopeKind
    @State private var names: String
    @Environment(\.dismiss) private var dismiss

    init(metric: Metric, onSave: @escaping (Metric) -> Void) {
        self.onSave = onSave
        id = metric.id
        _title = State(initialValue: metric.title)
        _filter = State(initialValue: metric.filter)
        switch metric.scope {
        case .everywhere:
            _scope = State(initialValue: .everywhere)
            _names = State(initialValue: "")
        case .organization(let name):
            _scope = State(initialValue: .organization)
            _names = State(initialValue: name)
        case .repositories(let repositories):
            _scope = State(initialValue: .repositories)
            _names = State(initialValue: repositories.joined(separator: ", "))
        }
    }

    var body: some View {
        let trimmedNames = names.trimmingCharacters(in: .whitespaces)
        let metricScope: MetricScope = switch scope {
        case .everywhere: .everywhere
        case .organization: .organization(trimmedNames)
        case .repositories: .repositories(names.split { $0 == "," || $0.isWhitespace }.map(String.init))
        }
        let metric = Metric(
            id: id,
            title: title.trimmingCharacters(in: .whitespaces),
            filter: filter.trimmingCharacters(in: .whitespaces),
            scope: metricScope
        )
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("PRs to review"))
                    TextField(text: $filter, prompt: Text("is:pr is:open review-requested:@me")) {
                        Text("Filter").font(.body)
                    }
                    .font(.body.monospaced())
                    Picker("Scope", selection: $scope) {
                        Text("Everywhere").tag(ScopeKind.everywhere)
                        Text("Organization").tag(ScopeKind.organization)
                        Text("Repositories").tag(ScopeKind.repositories)
                    }
                    .pickerStyle(.segmented)
                    if scope == .organization {
                        TextField("Organization", text: $names, prompt: Text("octo"))
                    } else if scope == .repositories {
                        TextField("Repositories", text: $names, prompt: Text("octo/app, octo/lib"))
                    }
                } footer: {
                    Text(scope == .everywhere
                        ? "Uses GitHub search syntax. To search everywhere, include @me, user:, org:, repo: or owner: in the filter."
                        : "Uses GitHub search syntax.")
                }
            }
            .formStyle(.grouped)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(metric)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!metric.isValid)
            }
            .padding(20)
        }
        .frame(width: 520, height: 320)
    }
}

private enum ScopeKind {
    case everywhere, organization, repositories
}
