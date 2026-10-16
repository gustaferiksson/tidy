import Foundation

public struct NotificationThread: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public var reason: Reason
  public var unread: Bool
  public var updatedAt: Date
  public var lastReadAt: Date?
  public var subject: Subject
  public var repository: Repository

  public init(
    id: String,
    reason: Reason,
    unread: Bool,
    updatedAt: Date,
    lastReadAt: Date? = nil,
    subject: Subject,
    repository: Repository
  ) {
    self.id = id
    self.reason = reason
    self.unread = unread
    self.updatedAt = updatedAt
    self.lastReadAt = lastReadAt
    self.subject = subject
    self.repository = repository
  }

  enum CodingKeys: String, CodingKey {
    case id, reason, unread, subject, repository
    case updatedAt = "updated_at"
    case lastReadAt = "last_read_at"
  }

  public var number: Int? {
    guard let url = subject.url, [.pullRequest, .issue, .discussion].contains(subject.kind) else { return nil }
    return Int(url.lastPathComponent)
  }

  public var ciState: SubjectState? {
    guard subject.kind == .checkSuite || subject.kind == .workflowRun else { return nil }
    let title = subject.title.lowercased()
    if title.contains("failed") { return .failed }
    if title.contains("cancelled") || title.contains("canceled") { return .cancelled }
    if title.contains("succeeded") { return .succeeded }
    return nil
  }
}

public struct Subject: Codable, Hashable, Sendable {
  public var title: String
  public var kind: SubjectKind
  public var url: URL?
  public var latestCommentURL: URL?

  public init(title: String, kind: SubjectKind, url: URL? = nil, latestCommentURL: URL? = nil) {
    self.title = title
    self.kind = kind
    self.url = url
    self.latestCommentURL = latestCommentURL
  }

  enum CodingKeys: String, CodingKey {
    case title, url
    case kind = "type"
    case latestCommentURL = "latest_comment_url"
  }
}

public struct Repository: Codable, Hashable, Sendable {
  public var fullName: String
  public var owner: GitHubUser
  public var isPrivate: Bool
  public var htmlURL: URL

  public init(fullName: String, owner: GitHubUser, isPrivate: Bool, htmlURL: URL) {
    self.fullName = fullName
    self.owner = owner
    self.isPrivate = isPrivate
    self.htmlURL = htmlURL
  }

  enum CodingKeys: String, CodingKey {
    case owner
    case fullName = "full_name"
    case isPrivate = "private"
    case htmlURL = "html_url"
  }
}

public struct GitHubUser: Codable, Hashable, Sendable {
  public var login: String
  public var avatarURL: URL?

  public init(login: String, avatarURL: URL? = nil) {
    self.login = login
    self.avatarURL = avatarURL
  }

  enum CodingKeys: String, CodingKey {
    case login
    case avatarURL = "avatar_url"
  }
}

public enum SubjectKind: RawRepresentable, Codable, Hashable, Sendable {
  case pullRequest
  case issue
  case discussion
  case release
  case commit
  case checkSuite
  case workflowRun
  case dependabotAlerts
  case secretScanningAlert
  case repositoryAdvisory
  case securityAdvisoryCredit
  case repositoryInvitation
  case unknown(String)

  public init(rawValue: String) {
    self =
      switch rawValue {
      case "PullRequest": .pullRequest
      case "Issue": .issue
      case "Discussion": .discussion
      case "Release": .release
      case "Commit": .commit
      case "CheckSuite": .checkSuite
      case "WorkflowRun": .workflowRun
      case "RepositoryDependabotAlertsThread", "RepositoryVulnerabilityAlert": .dependabotAlerts
      case "SecretScanningAlert": .secretScanningAlert
      case "RepositoryAdvisory": .repositoryAdvisory
      case "SecurityAdvisoryCredit": .securityAdvisoryCredit
      case "RepositoryInvitation": .repositoryInvitation
      default: .unknown(rawValue)
      }
  }

  public var rawValue: String {
    switch self {
    case .pullRequest: "PullRequest"
    case .issue: "Issue"
    case .discussion: "Discussion"
    case .release: "Release"
    case .commit: "Commit"
    case .checkSuite: "CheckSuite"
    case .workflowRun: "WorkflowRun"
    case .dependabotAlerts: "RepositoryDependabotAlertsThread"
    case .secretScanningAlert: "SecretScanningAlert"
    case .repositoryAdvisory: "RepositoryAdvisory"
    case .securityAdvisoryCredit: "SecurityAdvisoryCredit"
    case .repositoryInvitation: "RepositoryInvitation"
    case .unknown(let raw): raw
    }
  }

  public var title: String {
    switch self {
    case .pullRequest: "Pull request"
    case .issue: "Issue"
    case .discussion: "Discussion"
    case .release: "Release"
    case .commit: "Commit"
    case .checkSuite: "Check suite"
    case .workflowRun: "Workflow run"
    case .dependabotAlerts: "Dependabot alerts"
    case .secretScanningAlert: "Secret scanning alert"
    case .repositoryAdvisory: "Repository advisory"
    case .securityAdvisoryCredit: "Security advisory credit"
    case .repositoryInvitation: "Repository invitation"
    case .unknown(let raw): raw
    }
  }

  public var category: SubjectCategory {
    switch self {
    case .pullRequest: .pullRequest
    case .issue: .issue
    case .discussion: .discussion
    case .release: .release
    case .commit: .commit
    case .checkSuite, .workflowRun: .ci
    case .dependabotAlerts, .secretScanningAlert, .repositoryAdvisory, .securityAdvisoryCredit: .securityAlert
    case .repositoryInvitation, .unknown: .other
    }
  }

  public var isSecurity: Bool { category == .securityAlert }
}

public enum SubjectCategory: String, Codable, CaseIterable, Hashable, Sendable {
  case pullRequest, issue, securityAlert, release, discussion, ci, commit, other

  public var title: String {
    switch self {
    case .pullRequest: "Pull Request"
    case .issue: "Issue"
    case .securityAlert: "Security Alert"
    case .release: "Release"
    case .discussion: "Discussion"
    case .ci: "CI"
    case .commit: "Commit"
    case .other: "Other"
    }
  }
}

public struct Reason: RawRepresentable, Codable, Hashable, Sendable, Comparable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let approvalRequested = Reason(rawValue: "approval_requested")
  public static let assign = Reason(rawValue: "assign")
  public static let author = Reason(rawValue: "author")
  public static let comment = Reason(rawValue: "comment")
  public static let ciActivity = Reason(rawValue: "ci_activity")
  public static let invitation = Reason(rawValue: "invitation")
  public static let manual = Reason(rawValue: "manual")
  public static let memberFeatureRequested = Reason(rawValue: "member_feature_requested")
  public static let mention = Reason(rawValue: "mention")
  public static let reviewRequested = Reason(rawValue: "review_requested")
  public static let securityAlert = Reason(rawValue: "security_alert")
  public static let securityAdvisoryCredit = Reason(rawValue: "security_advisory_credit")
  public static let stateChange = Reason(rawValue: "state_change")
  public static let subscribed = Reason(rawValue: "subscribed")
  public static let teamMention = Reason(rawValue: "team_mention")

  public static let allKnown: [Reason] = [
    .reviewRequested, .approvalRequested, .mention, .teamMention, .assign, .author, .comment, .manual,
    .securityAlert, .securityAdvisoryCredit,
    .stateChange, .subscribed, .ciActivity, .invitation, .memberFeatureRequested,
  ]

  private static let titles: [Reason: String] = [
    .approvalRequested: "Approval requested",
    .assign: "Assigned",
    .author: "Author",
    .comment: "Comment",
    .ciActivity: "CI activity",
    .invitation: "Invitation",
    .manual: "Subscribed manually",
    .memberFeatureRequested: "Feature requested",
    .mention: "Mentioned",
    .reviewRequested: "Review requested",
    .securityAlert: "Security alert",
    .securityAdvisoryCredit: "Advisory credit",
    .stateChange: "State changed",
    .subscribed: "Watching",
    .teamMention: "Team mentioned",
  ]

  public var title: String {
    if let title = Self.titles[self] { return title }
    let spaced = rawValue.replacingOccurrences(of: "_", with: " ")
    return spaced.prefix(1).uppercased() + spaced.dropFirst()
  }

  public var group: ReasonGroup {
    if [.securityAlert, .securityAdvisoryCredit].contains(self) { return .security }
    if [.stateChange, .subscribed, .ciActivity, .invitation, .memberFeatureRequested].contains(self) { return .activity }
    return .participating
  }

  public static func < (lhs: Reason, rhs: Reason) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum ReasonGroup: String, Codable, CaseIterable, Hashable, Sendable {
  case participating, security, activity

  public var title: String {
    switch self {
    case .participating: "Participating"
    case .security: "Security"
    case .activity: "Activity"
    }
  }

  public var reasons: [Reason] { Reason.allKnown.filter { $0.group == self } }
}

public enum SubjectState: String, Codable, CaseIterable, Hashable, Sendable {
  case open, draft, merged, closed, notPlanned, answered, failed, succeeded, cancelled

  public var title: String {
    switch self {
    case .open: "Open"
    case .draft: "Draft"
    case .merged: "Merged"
    case .closed: "Closed"
    case .notPlanned: "Not planned"
    case .answered: "Answered"
    case .failed: "Failed"
    case .succeeded: "Succeeded"
    case .cancelled: "Cancelled"
    }
  }

  public static let filterable: [SubjectState] = [.open, .draft, .merged, .closed, .notPlanned]
}

public enum Severity: String, Codable, CaseIterable, Comparable, Hashable, Sendable {
  case low, moderate, high, critical

  public init?(apiValue: String?) {
    switch apiValue?.lowercased() {
    case "low": self = .low
    case "moderate", "medium": self = .moderate
    case "high": self = .high
    case "critical": self = .critical
    default: return nil
    }
  }

  public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

  public static func < (lhs: Severity, rhs: Severity) -> Bool {
    allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
  }
}
