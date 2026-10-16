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

public struct StateGlyph: Hashable, Sendable {
  public let symbol: String
  public let tone: StateTone
  public let label: String

  public init(symbol: String, tone: StateTone, label: String) {
    self.symbol = symbol
    self.tone = tone
    self.label = label
  }

  public init(kind: SubjectKind, state: SubjectState?, severity: Severity? = nil) {
    let (symbol, tone) = Self.appearance(kind: kind, state: state, severity: severity)
    let detail = kind.isSecurity ? severity?.title : state?.title
    self.init(symbol: symbol, tone: tone, label: [kind.title, detail?.lowercased()].compactMap(\.self).joined(separator: ", "))
  }

  public static func baseSymbol(for kind: SubjectKind) -> String {
    appearance(kind: kind, state: nil, severity: nil).0
  }

  private static func appearance(kind: SubjectKind, state: SubjectState?, severity: Severity?) -> (String, StateTone) {
    switch kind {
    case .pullRequest:
      switch state {
      case .merged: ("arrow.triangle.merge", .purple)
      case .open: ("arrow.triangle.pull", .green)
      case .closed: ("arrow.triangle.pull", .red)
      default: ("arrow.triangle.pull", .grey)
      }
    case .issue:
      switch state {
      case .open: ("smallcircle.filled.circle", .green)
      case .closed: ("checkmark.circle", .purple)
      case .notPlanned: ("circle.slash", .grey)
      default: ("smallcircle.filled.circle", .grey)
      }
    case .discussion:
      switch state {
      case .answered: ("checkmark.bubble", .purple)
      case .open: ("bubble.left.and.bubble.right", .green)
      default: ("bubble.left.and.bubble.right", .grey)
      }
    case .release: ("tag", .grey)
    case .commit: ("circle.and.line.horizontal", .grey)
    case .checkSuite, .workflowRun:
      switch state {
      case .failed: ("xmark.circle", .red)
      case .succeeded: ("checkmark.circle", .green)
      case .cancelled: ("circle.slash", .grey)
      default: ("bell", .grey)
      }
    case .dependabotAlerts: ("exclamationmark.shield.fill", state == nil ? .grey : StateTone(severity: severity))
    case .secretScanningAlert: ("key.viewfinder", state == nil ? .grey : .red)
    case .repositoryAdvisory: ("shield.lefthalf.filled", state == nil ? .grey : StateTone(severity: severity))
    case .securityAdvisoryCredit: ("checkmark.seal", .purple)
    case .repositoryInvitation: ("person.badge.plus", .grey)
    case .unknown: ("bell", .grey)
    }
  }
}
