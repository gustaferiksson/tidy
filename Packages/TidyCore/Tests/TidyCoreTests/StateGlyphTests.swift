import Testing

@testable import TidyCore

struct StateGlyphTests {
  @Test(arguments: [
    (SubjectKind.pullRequest, SubjectState?.some(.open), "arrow.triangle.pull", StateTone.green),
    (.pullRequest, .draft, "arrow.triangle.pull", .grey),
    (.pullRequest, .closed, "arrow.triangle.pull", .red),
    (.pullRequest, .merged, "arrow.triangle.merge", .purple),
    (.issue, .open, "smallcircle.filled.circle", .green),
    (.issue, .closed, "checkmark.circle", .purple),
    (.issue, .notPlanned, "circle.slash", .grey),
    (.discussion, .open, "bubble.left.and.bubble.right", .green),
    (.discussion, .answered, "checkmark.bubble", .purple),
    (.release, nil, "tag", .grey),
    (.commit, nil, "circle.and.line.horizontal", .grey),
    (.checkSuite, .failed, "xmark.circle", .red),
    (.workflowRun, .succeeded, "checkmark.circle", .green),
    (.checkSuite, .cancelled, "circle.slash", .grey),
    (.secretScanningAlert, .open, "key.viewfinder", .red),
    (.securityAdvisoryCredit, nil, "checkmark.seal", .purple),
    (.repositoryInvitation, nil, "person.badge.plus", .grey),
    (.unknown("Thing"), nil, "bell", .grey),
  ])
  func matchesFlowTable(kind: SubjectKind, state: SubjectState?, symbol: String, tone: StateTone) {
    let glyph = StateGlyph(kind: kind, state: state)
    #expect(glyph.symbol == symbol)
    #expect(glyph.tone == tone)
  }

  @Test(arguments: [
    (Severity?.some(.critical), StateTone.red), (.high, .orange), (.moderate, .yellow), (.low, .grey), (nil, .grey),
  ])
  func dependabotUsesHighestSeverity(severity: Severity?, tone: StateTone) {
    let glyph = StateGlyph(kind: .dependabotAlerts, state: .open, severity: severity)
    #expect(glyph.symbol == "exclamationmark.shield.fill")
    #expect(glyph.tone == tone)
    #expect(StateGlyph(kind: .repositoryAdvisory, state: .open, severity: severity).tone == tone)
  }

  @Test(arguments: [
    SubjectKind.pullRequest, .issue, .discussion, .dependabotAlerts, .secretScanningAlert, .repositoryAdvisory,
  ])
  func loadingOrFailedStateIsBaseSymbolInGrey(kind: SubjectKind) {
    let glyph = StateGlyph(kind: kind, state: nil)
    #expect(glyph.tone == .grey)
    #expect(glyph.symbol == StateGlyph.baseSymbol(for: kind))
  }

  @Test func labelsNameKindAndState() {
    #expect(StateGlyph(kind: .pullRequest, state: .draft).label == "Pull request, draft")
    #expect(StateGlyph(kind: .issue, state: .notPlanned).label == "Issue, not planned")
    #expect(StateGlyph(kind: .dependabotAlerts, state: .open, severity: .critical).label == "Dependabot alerts, critical")
    #expect(StateGlyph(kind: .release, state: nil).label == "Release")
  }
}
