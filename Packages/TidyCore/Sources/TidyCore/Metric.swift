import Foundation

public struct Metric: Codable, Hashable, Sendable, Identifiable {
  public var id: UUID
  public var title: String
  public var sources: [String]
  public var filter: String

  public init(id: UUID = UUID(), title: String, sources: [String] = [], filter: String) {
    self.id = id
    self.title = title
    self.sources = sources
    self.filter = filter
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, sources, filter
  }

  private enum LegacyKeys: String, CodingKey {
    case scope
  }

  private enum LegacyScope: Decodable {
    case everywhere
    case organization(String)
    case repositories([String])
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    filter = try container.decode(String.self, forKey: .filter)
    if let sources = try container.decodeIfPresent([String].self, forKey: .sources) {
      self.sources = sources
      return
    }
    let scope = try decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(LegacyScope.self, forKey: .scope)
    sources =
      switch scope {
      case .organization(let name): [name]
      case .repositories(let names): names
      case .everywhere, nil: []
      }
  }

  public static var presets: [Metric] {
    [
      Metric(title: "PRs to review", filter: "is:pr is:open review-requested:@me"),
      Metric(title: "My open PRs", filter: "is:pr is:open author:@me"),
      Metric(title: "Assigned to me", filter: "is:open assignee:@me"),
      Metric(title: "Issues to triage", sources: ["@me"], filter: "is:issue is:open no:label"),
    ]
  }

  public static var defaults: [Metric] { Array(presets.prefix(3)) }

  private static let sourceQualifiers = ["user:", "org:", "owner:", "repo:"]

  public var searchQuery: String {
    (sources.map { source in
      if Self.sourceQualifiers.contains(where: source.lowercased().hasPrefix) { return source }
      return source.contains("/") ? "repo:\(source)" : "user:\(source)"
    } + [filter])
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  public var webURL: URL? {
    var components = URLComponents(string: "https://github.com/search")
    components?.queryItems = [URLQueryItem(name: "q", value: searchQuery), URLQueryItem(name: "type", value: "issues")]
    let encodedQuery = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    components?.percentEncodedQuery = encodedQuery
    return components?.url
  }

  public var glyph: StateGlyph {
    let terms = filter.lowercased().split(separator: " ")
    if terms.contains("is:pr") { return StateGlyph(octicon: .gitPullRequest, tone: .green, label: "Pull requests") }
    if terms.contains("is:issue") { return StateGlyph(octicon: .issueOpened, tone: .green, label: "Issues") }
    return StateGlyph(octicon: .dotFill, tone: .grey, label: "Issues and pull requests")
  }

  public var isValid: Bool {
    !title.trimmingCharacters(in: .whitespaces).isEmpty && isSearchValid
  }

  public var isSearchValid: Bool {
    let sourcesAreValid = sources.allSatisfy { source in
      let colon = source.firstIndex(of: ":")
      if let colon, !Self.sourceQualifiers.contains(source[...colon].lowercased()) { return false }
      let name = colon.map { source[source.index(after: $0)...] } ?? source[...]
      let parts = name.split(separator: "/", omittingEmptySubsequences: false)
      return parts.count <= 2 && parts.allSatisfy { !$0.isEmpty && !$0.contains(where: \.isWhitespace) }
    }
    guard sourcesAreValid else { return false }
    guard sources.isEmpty else { return true }
    return filter.lowercased().split(whereSeparator: \.isWhitespace).contains { term in
      guard !term.hasPrefix("-"), !term.contains("\""), let colon = term.firstIndex(of: ":") else { return false }
      let value = term[term.index(after: colon)...]
      return value == "@me" || (["user", "org", "repo", "owner"].contains(term[..<colon]) && !value.isEmpty)
    }
  }
}
