import Foundation

public enum FilterCondition: Codable, Hashable, Sendable {
  case repository(String)
  case notRepository(String)
  case reason(Reason)
  case category(SubjectCategory)
  case author(String)
  case state(SubjectState)

  public static let authorPresets = ["dependabot[bot]", "renovate[bot]"]

  public var needsSubject: Bool {
    switch self {
    case .author, .state: true
    case .repository, .notRepository, .reason, .category: false
    }
  }

  public func matches(_ item: InboxItem) -> Bool? {
    let repository = item.thread.repository
    switch self {
    case .repository(let name), .notRepository(let name):
      let target = name.contains("/") ? repository.fullName : repository.owner.login
      let isMatch = target.caseInsensitiveCompare(name) == .orderedSame
      return if case .repository = self { isMatch } else { !isMatch }
    case .reason(let reason): return item.thread.reason == reason
    case .category(let category): return item.thread.subject.kind.category == category
    case .author(let login):
      guard item.status != .loading else { return nil }
      return item.author?.login.caseInsensitiveCompare(login) == .orderedSame
    case .state(let state):
      if let current = item.state { return current == state }
      return item.status == .loading ? nil : false
    }
  }
}

public enum RuleAction: String, Codable, CaseIterable, Hashable, Sendable {
  case hide, dontNotify, hideAndMarkRead, hideAndMarkDone

  public var title: String {
    switch self {
    case .hide: "Hide"
    case .dontNotify: "Don't Notify"
    case .hideAndMarkRead: "Hide and Mark Read"
    case .hideAndMarkDone: "Hide and Mark Done"
    }
  }

  public var hides: Bool { self != .dontNotify }
  public var isOptIn: Bool { self == .hideAndMarkRead || self == .hideAndMarkDone }
}

public struct FilterRule: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var conditions: [FilterCondition]
  public var action: RuleAction
  public var savedAt: Date

  public init(id: UUID = UUID(), conditions: [FilterCondition], action: RuleAction = .hide, savedAt: Date = .now) {
    self.id = id
    self.conditions = conditions
    self.action = action
    self.savedAt = savedAt
  }

  public var needsSubject: Bool { conditions.contains(where: \.needsSubject) }

  public func matches(_ item: InboxItem) -> Bool? {
    let results = conditions.map { $0.matches(item) }
    if conditions.isEmpty || results.contains(false) { return false }
    return results.contains(nil) ? nil : true
  }
}

public enum FilterOutcome: Hashable, Sendable {
  case none
  case undetermined
  case matched(FilterRule)

  public var hides: Bool {
    guard case .matched(let rule) = self else { return false }
    return rule.action.hides
  }

  public var silences: Bool {
    guard case .matched = self else { return false }
    return true
  }
}

extension [FilterRule] {
  public func outcome(for item: InboxItem) -> FilterOutcome {
    for rule in self {
      let match = rule.matches(item)
      if match == true { return .matched(rule) }
      if match == nil { return .undetermined }
    }
    return .none
  }
}
