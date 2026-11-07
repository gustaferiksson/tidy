import SwiftUI
import TidyCore

struct MetricSettings: View {
    @Bindable var settings: AppSettings
    @Environment(InboxStore.self) private var store
    @State private var selection = Set<UUID>()
    @State private var editing: Metric?

    var body: some View {
        Form {
            Section("Panel") {
                Toggle("Show metrics in the panel", isOn: $settings.showsMetrics)
                LabeledContent("Style") {
                    HStack(spacing: 12) {
                        ForEach(MetricStyle.allCases, id: \.self) { style in
                            SketchOption(value: style, title: style == .card ? "Card" : "Compact", selection: $settings.metricStyle) {
                                TileSketch(count: 3, columns: 3, size: CGSize(width: 26, height: style == .card ? 18 : 10))
                            }
                            .frame(width: 96)
                        }
                    }
                }
                .disabled(!settings.showsMetrics)
                LabeledContent("Layout") {
                    HStack(spacing: 12) {
                        ForEach(MetricLayout.allCases, id: \.self) { layout in
                            let title = switch layout {
                            case .scroll: "Scroll"
                            case .row: "One Row"
                            case .grid: "Grid"
                            }
                            SketchOption(value: layout, title: title, selection: $settings.metricLayout) {
                                if layout == .scroll {
                                    TileSketch(count: 4, columns: 4, size: CGSize(width: 22, height: 14))
                                        .frame(width: 72, alignment: .leading)
                                        .clipped()
                                        .mask(LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                                } else if layout == .row {
                                    TileSketch(count: 4, columns: 4, size: CGSize(width: 16, height: 14))
                                } else {
                                    TileSketch(count: 4, columns: 2, size: CGSize(width: 34, height: 8))
                                }
                            }
                            .frame(width: 96)
                        }
                    }
                }
                .disabled(!settings.showsMetrics)
            }

            Section {
                List(selection: $selection) {
                    ForEach(store.metrics) { metric in
                        MetricRow(metric: metric, result: store.metricResults[metric.id])
                    }
                    .onMove { store.metrics.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(height: 176)
                .overlay {
                    if store.metrics.isEmpty {
                        Text("No Metrics")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
                }
                .onDeleteCommand(perform: removeSelected)
                .contextMenu(forSelectionType: UUID.self) { ids in
                    Button("Edit…") { editing = store.metrics.first { ids.contains($0.id) } }
                        .disabled(ids.count != 1)
                    Button("Delete", role: .destructive) {
                        store.metrics.removeAll { ids.contains($0.id) }
                        selection.subtract(ids)
                    }
                } primaryAction: { ids in
                    editing = store.metrics.first { ids.contains($0.id) }
                }
                HStack(spacing: 4) {
                    Menu {
                        ForEach(Metric.presets, id: \.title) { preset in
                            Button(preset.title) { editing = preset }
                        }
                        Divider()
                        Button("Custom…") { editing = Metric(title: "", filter: "") }
                    } label: {
                        Label("Add Metric", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button("Remove", systemImage: "minus", action: removeSelected)
                        .labelStyle(.iconOnly)
                        .disabled(selection.isEmpty)
                    Spacer()
                    Button("Edit…") { editing = store.metrics.first { selection.contains($0.id) } }
                        .disabled(selection.count != 1)
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Metrics")
            } footer: {
                Text("Each metric counts a GitHub search. Click its tile in the panel to show only matching notifications. Drag to reorder.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 600)
        .sheet(item: $editing) { metric in
            let index = store.metrics.firstIndex { $0.id == metric.id }
            MetricEditor(metric: metric) { saved in
                guard let index else { return store.metrics.append(saved) }
                store.metrics[index] = saved
            }
        }
        #if DEBUG
        .onAppear {
            guard SettingsSnapshot.scene == "metricEditor" else { return }
            editing = store.metrics.first
        }
        #endif
    }

    private func removeSelected() {
        store.metrics.removeAll { selection.contains($0.id) }
        selection = []
    }
}

private struct MetricRow: View {
    let metric: Metric
    let result: Result<SearchResult, GitHubError>?

    var body: some View {
        HStack(spacing: 8) {
            StateGlyphView(glyph: metric.glyph)
            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .lineLimit(1)
                Text(metric.searchQuery)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text((try? result?.get()).map { $0.totalCount.formatted() } ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct TileSketch: View {
    let count: Int
    let columns: Int
    let size: CGSize

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(Array(stride(from: 0, to: count, by: columns)), id: \.self) { _ in
                GridRow {
                    ForEach(0..<columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .frame(width: size.width, height: size.height)
                    }
                }
            }
        }
        .foregroundStyle(.tertiary)
    }
}
