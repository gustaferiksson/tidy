import AppKit
import SwiftUI
import TidyCore

struct KeyboardSettings: View {
    @Bindable var settings: AppSettings
    @State private var recording: ShortcutAction?
    @State private var issue: ShortcutIssue?

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        VStack(alignment: .trailing, spacing: 4) {
                            ShortcutRecorder(
                                shortcut: settings.shortcuts[action],
                                isRecording: Binding(
                                    get: { recording == action },
                                    set: { isOn in
                                        recording = isOn ? action : nil
                                        issue = nil
                                    }
                                ),
                                record: { record($0, for: action) }
                            )
                            if recording == action, let issue {
                                Text(issue.message)
                                    .font(.callout)
                                    .foregroundStyle(.red)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            } header: {
                Text("Inbox")
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("These work while the inbox panel is open. Click a shortcut and press new keys, ⌫ to clear it or Esc to cancel.")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Restore Defaults") {
                        recording = nil
                        settings.shortcuts = .defaults
                    }
                    .disabled(settings.shortcuts == .defaults)
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 260)
    }

    private func record(_ shortcut: KeyShortcut?, for action: ShortcutAction) {
        if let shortcut, let found = settings.shortcuts.issue(with: shortcut, for: action) {
            issue = found
            return
        }
        settings.shortcuts[action] = shortcut
        recording = nil
    }
}

private struct ShortcutRecorder: View {
    let shortcut: KeyShortcut?
    @Binding var isRecording: Bool
    let record: (KeyShortcut?) -> Void

    var body: some View {
        Button { isRecording.toggle() } label: {
            Text(isRecording ? "Type Shortcut" : shortcut?.displayString ?? "None")
                .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                .frame(width: 120, height: 24)
                .background(.quaternary, in: .rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isRecording ? Color.accentColor : .clear, lineWidth: 2)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(KeyCatcher(isRecording: $isRecording, receive: receive))
        .accessibilityLabel(isRecording ? "Type Shortcut" : shortcut?.displayString ?? "None")
        .accessibilityHint("Records a new shortcut")
    }

    private func receive(_ event: NSEvent) {
        guard let pressed = KeyShortcut(event: event) else { return }
        if pressed.key == "\u{1b}" {
            isRecording = false
        } else if pressed.key == "\u{7f}" {
            record(nil)
        } else {
            record(pressed)
        }
    }
}

private struct KeyCatcher: NSViewRepresentable {
    @Binding var isRecording: Bool
    let receive: (NSEvent) -> Void

    func makeNSView(context: Context) -> KeyCatcherView { KeyCatcherView() }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.receive = receive
        view.resign = { if isRecording { isRecording = false } }
        let isFirstResponder = view.window?.firstResponder === view
        if isRecording, !isFirstResponder { view.window?.makeFirstResponder(view) }
        if !isRecording, isFirstResponder { view.window?.makeFirstResponder(nil) }
    }
}

private final class KeyCatcherView: NSView {
    var receive: ((NSEvent) -> Void)?
    var resign: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        receive?(event)
    }

    // ⌘ combos reach the window's key-equivalent pass before keyDown, so ⌘Q or ⌘W would otherwise act instead of recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        receive?(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        resign?()
        return true
    }
}
