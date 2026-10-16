public enum StateTone: String, Codable, CaseIterable, Hashable, Sendable {
  case green, purple, red, grey, orange, yellow

  public init(severity: Severity?) {
    self =
      switch severity {
      case .critical: .red
      case .high: .orange
      case .moderate: .yellow
      case .low, nil: .grey
      }
  }
}

public enum Octicon: String, CaseIterable, Sendable {
  case gitPullRequest = "git-pull-request"
  case gitPullRequestDraft = "git-pull-request-draft"
  case gitPullRequestClosed = "git-pull-request-closed"
  case gitMerge = "git-merge"
  case issueOpened = "issue-opened"
  case issueClosed = "issue-closed"
  case skip
  case commentDiscussion = "comment-discussion"
  case discussionClosed = "discussion-closed"
  case tag
  case gitCommit = "git-commit"
  case xCircle = "x-circle"
  case checkCircle = "check-circle"
  case stop
  case bell
  case dependabot
  case key
  case shield
  case shieldCheck = "shield-check"
  case personAdd = "person-add"
}

public struct StateGlyph: Hashable, Sendable {
  public let octicon: Octicon
  public let tone: StateTone
  public let label: String

  public init(octicon: Octicon, tone: StateTone, label: String) {
    self.octicon = octicon
    self.tone = tone
    self.label = label
  }

  public init(kind: SubjectKind, state: SubjectState?, severity: Severity? = nil) {
    let (octicon, tone) = Self.appearance(kind: kind, state: state, severity: severity)
    let detail = kind.isSecurity ? severity?.title : state?.title
    self.init(octicon: octicon, tone: tone, label: [kind.title, detail?.lowercased()].compactMap(\.self).joined(separator: ", "))
  }

  public static func baseOcticon(for kind: SubjectKind) -> Octicon {
    appearance(kind: kind, state: nil, severity: nil).0
  }

  private static func appearance(kind: SubjectKind, state: SubjectState?, severity: Severity?) -> (Octicon, StateTone) {
    switch kind {
    case .pullRequest:
      switch state {
      case .merged: (.gitMerge, .purple)
      case .open: (.gitPullRequest, .green)
      case .draft: (.gitPullRequestDraft, .grey)
      case .closed: (.gitPullRequestClosed, .red)
      default: (.gitPullRequest, .grey)
      }
    case .issue:
      switch state {
      case .open: (.issueOpened, .green)
      case .closed: (.issueClosed, .purple)
      case .notPlanned: (.skip, .grey)
      default: (.issueOpened, .grey)
      }
    case .discussion:
      switch state {
      case .answered: (.discussionClosed, .purple)
      case .open: (.commentDiscussion, .green)
      default: (.commentDiscussion, .grey)
      }
    case .release: (.tag, .grey)
    case .commit: (.gitCommit, .grey)
    case .checkSuite, .workflowRun:
      switch state {
      case .failed: (.xCircle, .red)
      case .succeeded: (.checkCircle, .green)
      case .cancelled: (.stop, .grey)
      default: (.bell, .grey)
      }
    case .dependabotAlerts: (.dependabot, state == nil ? .grey : StateTone(severity: severity))
    case .secretScanningAlert: (.key, state == nil ? .grey : .red)
    case .repositoryAdvisory: (.shield, state == nil ? .grey : StateTone(severity: severity))
    case .securityAdvisoryCredit: (.shieldCheck, .purple)
    case .repositoryInvitation: (.personAdd, .grey)
    case .unknown: (.bell, .grey)
    }
  }
}
