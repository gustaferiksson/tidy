import Foundation

public enum MetricScope: Codable, Hashable, Sendable {
  case everywhere
  case organization(String)
  case repositories([String])
}

public struct Metric: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var title: String
  public var filter: String
  public var scope: MetricScope

  public init(id: UUID = UUID(), title: String, filter: String, scope: MetricScope = .everywhere) {
    self.id = id
    self.title = title
    self.filter = filter
    self.scope = scope
  }

  public static var presets: [Metric] {
    [
      Metric(title: "PRs to review", filter: "is:pr is:open review-requested:@me"),
      Metric(title: "My open PRs", filter: "is:pr is:open author:@me"),
      Metric(title: "Assigned to me", filter: "is:open assignee:@me"),
      Metric(title: "Issues to triage", filter: "is:issue is:open no:label", scope: .organization("")),
    ]
  }

  public static var defaults: [Metric] { Array(presets.prefix(3)) }

  public var searchQuery: String {
    switch scope {
    case .everywhere: filter
    case .organization(let name): "org:\(name) \(filter)"
    case .repositories(let names): (names.map { "repo:\($0)" } + [filter]).joined(separator: " ")
    }
  }

  public var glyph: StateGlyph {
    let terms = filter.lowercased().split(separator: " ")
    if terms.contains("is:pr") { return StateGlyph(octicon: .gitPullRequest, tone: .green, label: "Pull requests") }
    if terms.contains("is:issue") { return StateGlyph(octicon: .issueOpened, tone: .green, label: "Issues") }
    return StateGlyph(octicon: .dotFill, tone: .grey, label: "Issues and pull requests")
  }

  public var isValid: Bool {
    guard !title.trimmingCharacters(in: .whitespaces).isEmpty, !filter.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
    switch scope {
    case .everywhere:
      return filter.lowercased().split(whereSeparator: \.isWhitespace).contains { term in
        guard !term.hasPrefix("-"), !term.contains("\""), let colon = term.firstIndex(of: ":") else { return false }
        let value = term[term.index(after: colon)...]
        return value == "@me" || (["user", "org", "repo", "owner"].contains(term[..<colon]) && !value.isEmpty)
      }
    case .organization(let name):
      return !name.isEmpty && !name.contains("/") && !name.contains(where: \.isWhitespace)
    case .repositories(let names):
      return !names.isEmpty && names.allSatisfy { name in
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
      }
    }
  }
}
