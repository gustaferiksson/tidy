import SwiftUI
import TidyCore

struct MetricEditor: View {
    let onSave: (Metric) -> Void
    private let id: UUID
    @State private var title: String
    @State private var sources: String
    @State private var filter: String
    @State private var preview: Result<SearchResult, GitHubError>?
    @Environment(InboxStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(metric: Metric, onSave: @escaping (Metric) -> Void) {
        self.onSave = onSave
        id = metric.id
        _title = State(initialValue: metric.title)
        _sources = State(initialValue: metric.sources.joined(separator: ", "))
        _filter = State(initialValue: metric.filter)
    }

    var body: some View {
        let metric = Metric(
            id: id,
            title: title.trimmingCharacters(in: .whitespaces),
            sources: sources.split { $0 == "," || $0.isWhitespace }.map(String.init),
            filter: filter.trimmingCharacters(in: .whitespaces)
        )
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Title", text: $title, prompt: Text("PRs to review"))
                    TextField("Sources", text: $sources, prompt: Text("octo, octo/app"))
                        .textInputSuggestions {
                            ForEach(sourceSuggestions, id: \.name) { suggestion in
                                Text(suggestion.name).textInputCompletion(suggestion.completion)
                            }
                        }
                    TextField(text: $filter, prompt: Text("is:pr is:open review-requested:@me")) {
                        Text("Search").font(.body)
                    }
                    .font(.body.monospaced())
                } footer: {
                    Group {
                        if !metric.isSearchValid {
                            Text("Add a source, or include @me, user:, org:, repo: or owner: in the search.")
                        } else if case .success(let result) = preview {
                            Text(result.totalCount == 1 ? "1 result" : "\(result.totalCount.formatted()) results")
                        } else if case .failure(let error) = preview {
                            Text(error == .invalidSearch ? "Invalid search" : error.message)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(width: 520, height: 270)
        .task(id: metric.isSearchValid ? metric.searchQuery : nil) {
            preview = nil
            guard metric.isSearchValid else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let result = await store.search(metric.searchQuery)
            guard !Task.isCancelled else { return }
            preview = result
        }
    }

    private var sourceSuggestions: [(name: String, completion: String)] {
        let typed = sources.split { $0 == "," || $0.isWhitespace }.map(String.init)
        let isTyping = sources.last.map { $0 != "," && !$0.isWhitespace } ?? false
        let partial = isTyping ? typed.last ?? "" : ""
        let kept = sources.dropLast(partial.count)
        let owners = Set(store.repositories.map { String($0.prefix { $0 != "/" }) }).sorted()
        return (owners + store.repositories)
            .filter { !typed.contains($0) && (partial.isEmpty || $0.localizedCaseInsensitiveContains(partial)) }
            .map { ($0, kept + $0) }
    }
}
