import SwiftUI
import TidyCore

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Bindable private var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInserted) {
            InboxPanel()
                .environment(appDelegate.store)
                .environment(appDelegate.panel)
                .environment(appDelegate.updater)
        } label: {
            MenuBarLabel(store: appDelegate.store, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
                .environment(appDelegate.updater)
                .environment(appDelegate.store)
        }
    }

    private var menuBarInserted: Binding<Bool> {
        #if DEBUG
        if InboxSnapshot.output != nil || SettingsSnapshot.output != nil { return .constant(false) }
        #endif
        return $settings.showMenuBarIcon
    }
}

private struct MenuBarLabel: View {
    let store: InboxStore
    let settings: AppSettings

    var body: some View {
        Image(nsImage: menuBarImage(store: store, style: settings.menuBarStyle, counting: settings.menuBarCount))
    }
}

// MenuBarExtra flattens its label to plain title text, so the glyph and count are drawn into one template image.
@MainActor
func menuBarImage(store: InboxStore, style: MenuBarStyle, counting: MenuBarCount = .unread) -> NSImage {
    let isBroken = !store.isSignedIn || store.issue == .unauthorized || store.issue == .missingScope
    let tracked = counting == .unread ? store.unreadCount : store.inbox.count { !store.rules.outcome(for: $0).hides }
    let count = isBroken ? 0 : tracked
    let font = NSFont.menuBarFont(ofSize: 0)
    let symbolName = style == .iconOnly && count > 0 ? "tray.badge" : "tray"
    let showsSymbol = count == 0 || style != .countOnly
    let showsCount = count > 0 && style != .iconOnly
    let symbol = showsSymbol
        ? NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular))
        : nil
    let title = NSAttributedString(
        string: showsCount ? (count > 99 ? "99+" : "\(count)") : "",
        attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)]
    )
    let symbolSize = symbol?.size ?? .zero
    let titleSize = title.size()
    let gap: CGFloat = symbol != nil && showsCount ? 4 : 0
    let height = max(symbolSize.height, titleSize.height).rounded(.up)
    let size = NSSize(width: (symbolSize.width + gap + titleSize.width).rounded(.up), height: height)
    let image = NSImage(size: size, flipped: false) { _ in
        symbol?.draw(in: NSRect(x: 0, y: (height - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height))
        title.draw(at: NSPoint(x: symbolSize.width + gap, y: (height - titleSize.height) / 2))
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = count > 0 ? "Tidy, \(count) \(counting == .unread ? "unread" : "not done")" : "Tidy"
    return image
}
