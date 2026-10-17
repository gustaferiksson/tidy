import Foundation

public struct KeyShortcut: Codable, Hashable, Sendable {
  public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
  }

  public let key: String
  public let modifiers: Modifiers

  public init(_ key: String, modifiers: Modifiers = []) {
    self.key = key.lowercased()
    self.modifiers = modifiers
  }

  private static let keyNames = [
    "\r": "↩", " ": "Space", "\t": "⇥", "\u{1b}": "⎋", "\u{7f}": "⌫",
    "\u{F700}": "↑", "\u{F701}": "↓", "\u{F702}": "←", "\u{F703}": "→",
  ]

  public var displayString: String {
    let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    let prefix = symbols.filter { modifiers.contains($0.0) }.map(\.1).joined()
    return prefix + (Self.keyNames[key] ?? key.uppercased())
  }
}

public enum ShortcutAction: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
  case done, markRead, muteThread

  public var title: String {
    switch self {
    case .done: "Done"
    case .markRead: "Mark as Read"
    case .muteThread: "Mute Thread"
    }
  }
}

public enum ShortcutIssue: Equatable, Sendable {
  case unsupported
  case reserved(KeyShortcut)
  case taken(KeyShortcut, by: ShortcutAction)

  public var message: String {
    switch self {
    case .unsupported: "Use a letter, number or symbol key, with or without modifiers."
    case .reserved(let shortcut): "\(shortcut.displayString) is already used in the inbox."
    case .taken(let shortcut, let action): "\(shortcut.displayString) is already used for \(action.title)."
    }
  }
}

public struct ShortcutBindings: Codable, Equatable, Sendable {
  public var shortcuts: [ShortcutAction: KeyShortcut]

  public init(_ shortcuts: [ShortcutAction: KeyShortcut]) {
    self.shortcuts = shortcuts
  }

  public static let defaults = ShortcutBindings([
    .done: KeyShortcut("e"),
    .markRead: KeyShortcut("i", modifiers: .shift),
    .muteThread: KeyShortcut("m", modifiers: .shift),
  ])

  static let reservedKeys: Set<String> = ["\u{F700}", "\u{F701}", "\r", " ", "\u{1b}"]
  static let reservedShortcuts: Set<KeyShortcut> = Set(["r", "z", "1", "2", ",", "q", "a", "[", "c"].map { KeyShortcut($0, modifiers: .command) })
    .union([KeyShortcut("i", modifiers: [.shift, .command])])

  public subscript(action: ShortcutAction) -> KeyShortcut? {
    get { shortcuts[action] }
    set { shortcuts[action] = newValue }
  }

  public func action(for shortcut: KeyShortcut) -> ShortcutAction? {
    ShortcutAction.allCases.first { shortcuts[$0] == shortcut }
  }

  public func issue(with shortcut: KeyShortcut, for action: ShortcutAction) -> ShortcutIssue? {
    if Self.reservedKeys.contains(shortcut.key) || Self.reservedShortcuts.contains(shortcut) {
      return .reserved(shortcut)
    }
    let scalars = shortcut.key.unicodeScalars
    let isPrintable = scalars.count == 1 && scalars.allSatisfy {
      !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) && !(0xF700...0xF8FF).contains($0.value)
    }
    guard isPrintable else { return .unsupported }
    guard let owner = self.action(for: shortcut), owner != action else { return nil }
    return .taken(shortcut, by: owner)
  }
}
