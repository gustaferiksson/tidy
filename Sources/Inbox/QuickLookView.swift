import AppKit
import SwiftUI
import TidyCore

struct QuickLookView: View {
    let id: String
    let order: [InboxItem]
    @Environment(InboxStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    panel.quickLookID = nil
                } label: {
                    Label("Inbox", systemImage: "chevron.backward")
                }
                .buttonStyle(.borderless)
                .help("Back to Inbox")
                Spacer()
                if let index = order.firstIndex(where: { $0.id == id }) {
                    Text("\(index + 1) of \(order.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            Divider()
            if let item {
                ScrollView {
                    details(of: item)
                        .padding(16)
                }
                Divider()
                actions(for: item)
            } else {
                ContentUnavailableView("Thread no longer in the inbox", systemImage: "tray")
                    .frame(maxHeight: .infinity)
            }
        }
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .focusable(interactions: .edit)
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) { step(by: -1) }
        .onKeyPress(.downArrow) { step(by: 1) }
        .onKeyPress(.space) {
            panel.quickLookID = nil
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            guard let item else { return .ignored }
            open(item, markingRead: !press.modifiers.contains(.option))
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "eI")) { press in
            guard let item, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            if press.characters == "I" { store.markRead([item.id]) } else { markDone(item) }
            return .handled
        }
    }

    private var item: InboxItem? {
        store.inbox.first { $0.id == id }
    }

    private func details(of item: InboxItem) -> some View {
        let rich = store.threadDetails(for: item)
        let state = rich?.details?.discussion?.isAnswered == true ? .answered : item.state
        let glyph = item.status == .failed
            ? StateGlyph(octicon: StateGlyph.baseOcticon(for: item.thread.subject.kind), tone: .grey, label: "State unavailable")
            : StateGlyph(kind: item.thread.subject.kind, state: state, severity: item.severity)
        let stateWord = item.status == .failed
            ? "State unavailable"
            : (item.thread.subject.kind.isSecurity ? item.severity?.title : state?.title) ?? item.thread.subject.kind.title
        let kindLine = [item.thread.subject.kind.title + (item.thread.number.map { " #\($0)" } ?? ""), item.thread.repository.fullName]
        let commenter = item.details?.latestComment?.author?.login
        let people = [
            item.author.map { "by \($0.login)" },
            commenter.flatMap { $0 == item.author?.login ? nil : "last comment by \($0)" },
        ].compactMap(\.self).joined(separator: ", ")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                StateGlyphView(glyph: glyph)
                Text(stateWord)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(glyph.tone == .grey ? .secondary : StateGlyphView.color(for: glyph.tone, scheme: scheme, contrast: contrast))
            }
            Text(kindLine.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(item.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                Text([people.isEmpty ? nil : people, item.thread.reason.title].compactMap(\.self).joined(separator: " · ") + " · ")
                Text(item.thread.updatedAt, format: .relative(presentation: .named))
                    .help(item.thread.updatedAt.formatted(date: .complete, time: .shortened))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            if !ThreadDetails.isSupported(item.thread) || rich == .unavailable {
                preview(of: item)
            } else if rich == .failed {
                HStack(spacing: 8) {
                    Text("Couldn't load the conversation").foregroundStyle(.secondary)
                    Button("Retry") { store.loadThreadDetails(for: item.id) }
                }
                .font(.subheadline)
                preview(of: item)
            } else {
                ThreadDetailsView(details: rich?.details).id(item.id)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(item.id)@\(item.thread.updatedAt.timeIntervalSince1970)") { store.loadThreadDetails(for: item.id) }
    }

    @ViewBuilder private func preview(of item: InboxItem) -> some View {
        if item.status == .loading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        } else if item.status == .failed {
            HStack(spacing: 8) {
                Text("Couldn't load details").foregroundStyle(.secondary)
                Button("Retry") { store.loadDetails(for: item.id) }
            }
        } else if let alerts = item.details?.alerts, !alerts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(alerts) { alert in
                    AlertRow(alert: alert)
                }
            }
        } else if let markdown = item.previewMarkdown, !markdown.isEmpty {
            MarkdownView(source: markdown)
        } else {
            Text("No description provided.").foregroundStyle(.secondary)
        }
    }

    private func actions(for item: InboxItem) -> some View {
        HStack(spacing: 8) {
            Button("Open on GitHub") { open(item, markingRead: true) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Button("Mark as Read") { store.markRead([item.id]) }
                .disabled(!item.isUnread)
            Button("Done") { markDone(item) }
            Spacer(minLength: 0)
            Menu {
                Button("Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.webURL.absoluteString, forType: .string)
                }
                Divider()
                Button("Mute Thread") { muteThread(item) }
                Button("Mute Repository") { store.muteRepository(item.thread.repository.fullName) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .imageScale(.large)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    private func step(by offset: Int) -> KeyPress.Result {
        guard let next = steppedSelection(from: [id], in: order.map(\.id), by: offset) else { return .handled }
        panel.showDetails(next)
        return .handled
    }

    private func open(_ item: InboxItem, markingRead: Bool) {
        if item.webURL.isGitHubWeb { NSWorkspace.shared.open(item.webURL) }
        if markingRead { store.markRead([item.id]) }
    }

    private func markDone(_ item: InboxItem) {
        showNext(after: item)
        store.markDone([item.id])
    }

    private func muteThread(_ item: InboxItem) {
        showNext(after: item)
        store.muteThread(item.id)
    }

    private func showNext(after item: InboxItem) {
        let index = order.firstIndex { $0.id == item.id }
        guard let next = index.flatMap({ order.indices.contains($0 + 1) ? order[$0 + 1].id : nil }) else {
            panel.selection = []
            panel.quickLookID = nil
            return
        }
        panel.showDetails(next)
    }
}

private struct AlertRow: View {
    let alert: SecurityAlert
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if let package = alert.package {
                    Text(package).fontWeight(.semibold)
                }
                if let severity = alert.severity {
                    let tint = StateGlyphView.color(for: StateTone(severity: severity), scheme: scheme, contrast: contrast)
                    Text(severity.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.16), in: .capsule)
                }
            }
            Text(alert.summary)
            if let advisoryID = alert.advisoryID {
                if let url = alert.htmlURL {
                    Link(advisoryID, destination: url).font(.subheadline)
                } else {
                    Text(advisoryID).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
