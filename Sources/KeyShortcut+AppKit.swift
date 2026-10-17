import AppKit
import SwiftUI
import TidyCore

extension KeyShortcut {
    init?(event: NSEvent) {
        guard event.type == .keyDown, let key = event.characters(byApplyingModifiers: []), !key.isEmpty else { return nil }
        let flags = event.modifierFlags
        self.init(key, modifiers: [
            flags.contains(.control) ? .control : [],
            flags.contains(.option) ? .option : [],
            flags.contains(.shift) ? .shift : [],
            flags.contains(.command) ? .command : [],
        ])
    }

    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: [
            modifiers.contains(.control) ? .control : [],
            modifiers.contains(.option) ? .option : [],
            modifiers.contains(.shift) ? .shift : [],
            modifiers.contains(.command) ? .command : [],
        ])
    }
}
