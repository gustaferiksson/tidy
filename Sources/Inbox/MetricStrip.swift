import SwiftUI
import TidyCore

struct MetricStrip: View {
    let style: MetricStyle
    let layout: MetricLayout
    @Environment(InboxStore.self) private var store

    var body: some View {
        Group {
            if layout == .scroll {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        tiles.frame(width: 116)
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.never)
            } else if layout == .row {
                HStack(spacing: 6) { tiles }
                    .padding(.horizontal, 12)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) { tiles }
                    .padding(.horizontal, 12)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var tiles: some View {
        ForEach(store.metrics) { metric in
            MetricTile(metric: metric, result: store.metricResults[metric.id], style: style, isActive: store.scope.metric == metric.id) {
                store.scope.metric = store.scope.metric == metric.id ? nil : metric.id
            }
        }
    }
}

private struct MetricTile: View {
    let metric: Metric
    let result: Result<SearchResult, GitHubError>?
    let style: MetricStyle
    let isActive: Bool
    let toggle: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let total = try? result?.get().totalCount
        let count = total.map { $0.formatted() } ?? "–"
        let failure: GitHubError? = if case .failure(let error)? = result { error } else { nil }
        let glyph = Image(metric.glyph.octicon.rawValue)
            .font(.system(size: 14))
            .foregroundStyle(StateGlyphView.color(for: metric.glyph.tone, scheme: scheme, contrast: contrast))
        Button(action: toggle) {
            Group {
                if style == .card {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(count)
                                .font(.title2.weight(.semibold))
                                .monospacedDigit()
                            Spacer(minLength: 0)
                            glyph
                        }
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 9)
                } else {
                    HStack(spacing: 7) {
                        glyph
                        Text(count)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                        Text(metric.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quaternary, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isActive ? Color.accentColor : .clear, lineWidth: 2)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(total == 0 && !isActive ? 0.45 : 1)
        .help(failure?.message ?? metric.searchQuery)
        .accessibilityLabel("\(metric.title), \(count)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
