import AppKit
import SwiftUI
import TidyCore

struct SearchResultRow: View {
    let result: SearchItem
    let now: Date
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        let secondary = prominence == .increased ? Color.white : .secondary
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            StateGlyphView(glyph: result.glyph)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .padding(.leading, 12)
                .padding(.trailing, 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(result.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortAge(of: result.updatedAt, now: now))
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(secondary)
                        .fixedSize()
                }
                HStack(spacing: 0) {
                    Text("\(result.repository) #\(result.number)")
                        .truncationMode(.middle)
                    if let author = result.author {
                        Text(" · \(author)")
                            .layoutPriority(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            guard NSEvent.modifierFlags.isDisjoint(with: [.command, .shift]), result.htmlURL.isGitHubWeb else { return }
            NSWorkspace.shared.open(result.htmlURL)
        })
        .help("Open on GitHub")
    }
}
