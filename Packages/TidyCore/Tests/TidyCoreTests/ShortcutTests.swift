import Foundation
import Testing

@testable import TidyCore

struct ShortcutTests {
  @Test func defaultsFollowGitHub() {
    let defaults = ShortcutBindings.defaults
    #expect(defaults[.done]?.displayString == "E")
    #expect(defaults[.markRead]?.displayString == "⇧I")
    #expect(defaults[.muteThread]?.displayString == "⇧M")
  }

  @Test func displayOrdersModifiersLikeMenus() {
    #expect(KeyShortcut("k", modifiers: [.command, .shift, .option, .control]).displayString == "⌃⌥⇧⌘K")
    #expect(KeyShortcut("\r", modifiers: .command).displayString == "⌘↩")
    #expect(KeyShortcut("\u{F700}").displayString == "↑")
  }

  @Test func keysAreStoredLowercased() {
    #expect(KeyShortcut("I", modifiers: .shift) == KeyShortcut("i", modifiers: .shift))
  }

  @Test func lookupNeedsExactModifiers() {
    let defaults = ShortcutBindings.defaults
    #expect(defaults.action(for: KeyShortcut("e")) == .done)
    #expect(defaults.action(for: KeyShortcut("i", modifiers: .shift)) == .markRead)
    #expect(defaults.action(for: KeyShortcut("m", modifiers: .shift)) == .muteThread)
    #expect(defaults.action(for: KeyShortcut("i")) == nil)
    #expect(defaults.action(for: KeyShortcut("e", modifiers: .command)) == nil)
  }

  @Test func rejectsPanelKeysWithAnyModifiers() {
    let defaults = ShortcutBindings.defaults
    for key in ["\u{F700}", "\u{F701}", "\r", " ", "\u{1b}"] {
      #expect(defaults.issue(with: KeyShortcut(key), for: .done) == .reserved(KeyShortcut(key)))
    }
    let openUnread = KeyShortcut("\r", modifiers: [.option, .command])
    #expect(defaults.issue(with: openUnread, for: .done) == .reserved(openUnread))
  }

  @Test func rejectsFixedKeyEquivalents() {
    let defaults = ShortcutBindings.defaults
    for shortcut in [KeyShortcut("r", modifiers: .command), KeyShortcut("1", modifiers: .command), KeyShortcut("i", modifiers: [.shift, .command])] {
      #expect(defaults.issue(with: shortcut, for: .muteThread) == .reserved(shortcut))
    }
    #expect(defaults.issue(with: KeyShortcut("r"), for: .muteThread) == nil)
  }

  @Test func rejectsNonPrintableKeys() {
    let defaults = ShortcutBindings.defaults
    #expect(defaults.issue(with: KeyShortcut("\t"), for: .done) == .unsupported)
    #expect(defaults.issue(with: KeyShortcut("\u{F704}"), for: .done) == .unsupported)
    #expect(defaults.issue(with: KeyShortcut(""), for: .done) == .unsupported)
  }

  @Test func rejectsAnotherActionsShortcutButNotItsOwn() {
    let defaults = ShortcutBindings.defaults
    let markRead = KeyShortcut("i", modifiers: .shift)
    #expect(defaults.issue(with: markRead, for: .done) == .taken(markRead, by: .markRead))
    #expect(defaults.issue(with: markRead, for: .markRead) == nil)
    #expect(ShortcutIssue.taken(markRead, by: .markRead).message == "⇧I is already used for Mark as Read.")
  }

  @Test func allowsLettersAndModifierCombos() {
    let defaults = ShortcutBindings.defaults
    #expect(defaults.issue(with: KeyShortcut("y"), for: .done) == nil)
    #expect(defaults.issue(with: KeyShortcut("e", modifiers: [.option, .command]), for: .done) == nil)
    #expect(defaults.issue(with: KeyShortcut("#", modifiers: .shift), for: .done) == nil)
  }

  @Test func roundTripsKeepingClearedActions() throws {
    var bindings = ShortcutBindings.defaults
    bindings[.muteThread] = nil
    bindings[.done] = KeyShortcut("d", modifiers: .control)
    let decoded = try JSONDecoder().decode(ShortcutBindings.self, from: JSONEncoder().encode(bindings))
    #expect(decoded == bindings)
    #expect(decoded[.muteThread] == nil)
  }
}
