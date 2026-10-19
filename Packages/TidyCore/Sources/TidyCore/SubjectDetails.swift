import Foundation

public struct SubjectDetails: Codable, Hashable, Sendable {
  public var state: SubjectState?
  public var author: GitHubUser?
  public var body: String?
  public var htmlURL: URL?
  public var latestComment: Comment?
  public var alerts: [SecurityAlert]

  public init(
    state: SubjectState? = nil,
    author: GitHubUser? = nil,
    body: String? = nil,
    htmlURL: URL? = nil,
    latestComment: Comment? = nil,
    alerts: [SecurityAlert] = []
  ) {
    self.state = state
    self.author = author
    self.body = body
    self.htmlURL = htmlURL
    self.latestComment = latestComment
    self.alerts = alerts
  }

  public var highestSeverity: Severity? { alerts.compactMap(\.severity).max() }
}

public struct Comment: Codable, Hashable, Sendable {
  public var apiURL: URL
  public var author: GitHubUser?
  public var body: String
  public var htmlURL: URL?
  public var review: ReviewState?

  public init(apiURL: URL, author: GitHubUser?, body: String, htmlURL: URL?, review: ReviewState? = nil) {
    self.apiURL = apiURL
    self.author = author
    self.body = body
    self.htmlURL = htmlURL
    self.review = review
  }
}

public struct SecurityAlert: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var package: String?
  public var severity: Severity?
  public var summary: String
  public var advisoryID: String?
  public var htmlURL: URL?

  public init(id: String, package: String?, severity: Severity?, summary: String, advisoryID: String?, htmlURL: URL?) {
    self.id = id
    self.package = package
    self.severity = severity
    self.summary = summary
    self.advisoryID = advisoryID
    self.htmlURL = htmlURL
  }
}

public enum DetailsStatus: Codable, Hashable, Sendable {
  case loading
  case loaded(SubjectDetails)
  case failed

  public var details: SubjectDetails? {
    guard case .loaded(let details) = self else { return nil }
    return details
  }
}

public struct InboxItem: Codable, Hashable, Sendable, Identifiable {
  public var thread: NotificationThread
  public var status: DetailsStatus

  public init(thread: NotificationThread, status: DetailsStatus = .loading) {
    self.thread = thread
    self.status = status
  }

  public var id: String { thread.id }
  public var details: SubjectDetails? { status.details }
  public var isUnread: Bool { thread.unread }
  public var state: SubjectState? { details?.state ?? thread.ciState }
  public var severity: Severity? { details?.highestSeverity }
  public var glyph: StateGlyph { StateGlyph(kind: thread.subject.kind, state: state, severity: severity) }
  public var webURL: URL { WebLink.url(for: thread, details: details) }
  public var author: GitHubUser? { details?.author }
  public var previewMarkdown: String? { details?.latestComment.flatMap { $0.body.isEmpty ? nil : $0.body } ?? details?.body }

  public var title: String {
    guard thread.subject.kind == .dependabotAlerts, let alerts = details?.alerts else { return thread.subject.title }
    if alerts.isEmpty { return "No open Dependabot alerts" }
    let counted = alerts.count == 1 ? "1 vulnerable dependency" : "\(alerts.count) vulnerable dependencies"
    guard let top = alerts.compactMap(\.severity).max() else { return counted }
    let topCount = alerts.filter { $0.severity == top }.count
    return "\(counted) · \(topCount) \(top.rawValue)"
  }
}
