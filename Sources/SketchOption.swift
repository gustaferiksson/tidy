import SwiftUI

struct SketchOption<Value: Hashable, Sketch: View>: View {
    let value: Value
    let title: String
    @Binding var selection: Value
    @ViewBuilder let sketch: Sketch
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let isSelected = selection == value
        Button { selection = value } label: {
            VStack(spacing: 8) {
                sketch
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(.quaternary, in: .rect(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    }
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
