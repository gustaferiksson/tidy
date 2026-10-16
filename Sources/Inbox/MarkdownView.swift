import SwiftUI

struct MarkdownView: View {
    let source: String
    @State private var blocks: [Block] = []

    static func plainFirstLine(of source: String) -> String {
        let line = blocks(from: source)
            .lazy
            .flatMap { String($0.text.characters).split(whereSeparator: \.isNewline) }
            .map { $0.replacing(/<\/?[A-Za-z][^>]*>/, with: "").trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 200 ? String(line.prefix(199)) + "…" : line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph:
                    Text(block.text)
                case .heading(let level):
                    Text(block.text)
                        .font(level <= 2 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, 4)
                case .code:
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(block.text)
                            .font(.system(.callout, design: .monospaced))
                            .fixedSize()
                            .padding(8)
                    }
                    .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 8))
                case .listItem(let marker, let depth):
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(marker)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(minWidth: 12, alignment: .trailing)
                        Text(block.text)
                    }
                    .padding(.leading, CGFloat(depth - 1) * 16)
                case .quote:
                    Text(block.text)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.tertiary).frame(width: 4)
                        }
                case .rule:
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: source, initial: true) { blocks = Self.blocks(from: source) }
    }

    private struct Block: Identifiable {
        enum Kind {
            case paragraph, code, quote, rule
            case heading(Int)
            case listItem(marker: String, depth: Int)
        }

        let id: Int
        let kind: Kind
        let text: AttributedString
    }

    private static func blocks(from source: String) -> [Block] {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        let linked = linkingHTML(in: source)
        guard var attributed = try? AttributedString(markdown: linked, options: options) else {
            return [Block(id: 0, kind: .paragraph, text: AttributedString(linked))]
        }
        for (imageURL, range) in attributed.runs[\.imageURL] {
            guard let imageURL else { continue }
            attributed[range].link = imageURL
        }
        var markedItems: Set<Int> = []
        return attributed.runs[\.presentationIntent].enumerated().map { index, run in
            let (intent, range) = run
            let components = intent?.components ?? []
            let text = AttributedString(attributed[range])
            if components.contains(where: { if case .codeBlock = $0.kind { true } else { false } }) {
                let code = String(text.characters).trimmingCharacters(in: .newlines)
                return Block(id: index, kind: .code, text: AttributedString(code))
            }
            if let itemIndex = components.firstIndex(where: { if case .listItem = $0.kind { true } else { false } }),
               case .listItem(let ordinal) = components[itemIndex].kind
            {
                let isFirst = markedItems.insert(components[itemIndex].identity).inserted
                let isOrdered = components.indices.contains(itemIndex + 1) && components[itemIndex + 1].kind == .orderedList
                let depth = components.count { if case .listItem = $0.kind { true } else { false } }
                let marker = isFirst ? (isOrdered ? "\(ordinal)." : "•") : ""
                return Block(id: index, kind: .listItem(marker: marker, depth: depth), text: text)
            }
            for component in components {
                if case .header(let level) = component.kind { return Block(id: index, kind: .heading(level), text: text) }
                if component.kind == .blockQuote { return Block(id: index, kind: .quote, text: text) }
                if component.kind == .thematicBreak { return Block(id: index, kind: .rule, text: text) }
            }
            return Block(id: index, kind: .paragraph, text: text)
        }
    }

    // Foundation's parser drops raw HTML, which GitHub bodies use for images, links and hidden comments.
    private static func linkingHTML(in source: String) -> String {
        source
            .replacing(/<!--[\s\S]*?-->/, with: "")
            .replacing(/<img[^>]*?src="([^"]+)"[^>]*>/) { "[Image](\($0.1))" }
            .replacing(/<a[^>]*?href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/) { "[\($0.2)](\($0.1))" }
            .replacing(/<\/?(?:details|summary|p|div|br|sub|sup|picture|source|b|i|em|strong|kbd|span)[^>]*>/, with: "")
    }
}
