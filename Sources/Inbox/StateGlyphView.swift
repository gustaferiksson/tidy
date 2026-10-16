import SwiftUI
import TidyCore

struct StateGlyphView: View {
    let glyph: StateGlyph
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Image(systemName: glyph.symbol)
            .font(.system(size: 16))
            .foregroundStyle(Self.color(for: glyph.tone, scheme: scheme, contrast: contrast))
            .frame(width: 20, height: 20)
            .help(glyph.label)
            .accessibilityLabel(glyph.label)
    }

    static func color(for tone: StateTone, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        let (light, dark, system): (UInt32, UInt32, Color) =
            switch tone {
            case .green: (0x1a7f37, 0x3fb950, .green)
            case .purple: (0x8250df, 0xa371f7, .purple)
            case .red: (0xd1242f, 0xf85149, .red)
            case .grey: (0x59636e, 0x9198a1, .gray)
            case .orange: (0xbc4c00, 0xdb6d28, .orange)
            case .yellow: (0x9a6700, 0xd29922, .yellow)
            }
        if contrast == .increased { return system }
        let hex = scheme == .dark ? dark : light
        return Color(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}
