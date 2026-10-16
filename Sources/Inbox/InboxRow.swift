import SwiftUI
import TidyCore

struct InboxRow: View {
    let item: InboxItem
    let isDone: Bool
    let now: Date
    @Environment(InboxStore.self) private var store
    @Environment(PanelController.self) private var panel
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Circle()
                .fill(item.isUnread ? Color.accentColor : .clear)
                .frame(width: 8, height: 8)
                .frame(width: 12)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                .accessibilityHidden(true)
            StateGlyphView(glyph: item.glyph)
                .opacity(item.isUnread ? 1 : 0.6)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(item.isUnread ? .semibold : .regular)
                    .foregroundStyle(item.isUnread ? .primary : .secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .redacted(reason: item.status == .loading ? .placeholder : [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .padding(.trailing, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .overlay(alignment: .trailing) {
            if isHovered { hoverButtons.padding(.trailing, 8) }
        }
        .onHover { isHovered = $0 }
        .simultaneousGesture(TapGesture(count: 2).onEnded { panel.quickLookID = item.id })
        .swipeActions(edge: .leading) {
            if item.isUnread {
                Button("Mark as Read", systemImage: "envelope.open") { store.markRead([item.id]) }
                    .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            if isDone {
                Button("Move to Inbox", systemImage: "tray.and.arrow.up") { store.moveToInbox([item.id]) }
            } else {
                Button("Done", systemImage: "checkmark") { store.markDone([item.id]) }
                    .tint(.green)
            }
        }
    }

    private var meta: String {
        let number = item.thread.number.map { " #\($0)" } ?? ""
        let severity = item.thread.subject.kind.isSecurity ? item.severity?.title : nil
        let state = differentiateWithoutColor ? item.state?.title : nil
        return [item.thread.repository.fullName + number, item.thread.reason.title, severity, state, shortAge(of: item.thread.updatedAt, now: now)]
            .compactMap(\.self)
            .joined(separator: " · ")
    }

    private var hoverButtons: some View {
        HStack(spacing: 0) {
            if isDone {
                hoverButton("Move to Inbox", symbol: "tray.and.arrow.up") { store.moveToInbox([item.id]) }
            } else {
                hoverButton("Mark as Read", symbol: "envelope.open") { store.markRead([item.id]) }
                    .disabled(!item.isUnread)
                hoverButton("Done", symbol: "checkmark") { store.markDone([item.id]) }
            }
        }
        .padding(.horizontal, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func hoverButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}
