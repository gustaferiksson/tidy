import Foundation
import Testing

@testable import TidyCore

struct StateGlyphTests {
  @Test(arguments: [
    (SubjectKind.pullRequest, SubjectState?.some(.open), Octicon.gitPullRequest, StateTone.green),
    (.pullRequest, .draft, .gitPullRequestDraft, .grey),
    (.pullRequest, .closed, .gitPullRequestClosed, .red),
    (.pullRequest, .merged, .gitMerge, .purple),
    (.issue, .open, .issueOpened, .green),
    (.issue, .closed, .issueClosed, .purple),
    (.issue, .notPlanned, .skip, .grey),
    (.discussion, .open, .commentDiscussion, .green),
    (.discussion, .answered, .discussionClosed, .purple),
    (.release, nil, .tag, .grey),
    (.commit, nil, .gitCommit, .grey),
    (.checkSuite, .failed, .xCircle, .red),
    (.workflowRun, .succeeded, .checkCircle, .green),
    (.checkSuite, .cancelled, .stop, .grey),
    (.secretScanningAlert, .open, .key, .red),
    (.securityAdvisoryCredit, nil, .shieldCheck, .purple),
    (.repositoryInvitation, nil, .personAdd, .grey),
    (.unknown("Thing"), nil, .bell, .grey),
  ])
  func matchesFlowTable(kind: SubjectKind, state: SubjectState?, octicon: Octicon, tone: StateTone) {
    let glyph = StateGlyph(kind: kind, state: state)
    #expect(glyph.octicon == octicon)
    #expect(glyph.tone == tone)
  }

  @Test(arguments: [
    (Severity?.some(.critical), StateTone.red), (.high, .orange), (.moderate, .yellow), (.low, .grey), (nil, .grey),
  ])
  func dependabotUsesHighestSeverity(severity: Severity?, tone: StateTone) {
    let glyph = StateGlyph(kind: .dependabotAlerts, state: .open, severity: severity)
    #expect(glyph.octicon == .dependabot)
    #expect(glyph.tone == tone)
    #expect(StateGlyph(kind: .repositoryAdvisory, state: .open, severity: severity).tone == tone)
  }

  @Test(arguments: [
    SubjectKind.pullRequest, .issue, .discussion, .dependabotAlerts, .secretScanningAlert, .repositoryAdvisory,
  ])
  func loadingOrFailedStateIsBaseOcticonInGrey(kind: SubjectKind) {
    let glyph = StateGlyph(kind: kind, state: nil)
    #expect(glyph.tone == .grey)
    #expect(glyph.octicon == StateGlyph.baseOcticon(for: kind))
  }

  @Test(arguments: Octicon.allCases)
  func everyOcticonHasASymbolInTheAppCatalog(octicon: Octicon) {
    let symbolset = URL(filePath: #filePath)
      .deletingLastPathComponent()
      .appending(path: "../../../../Resources/Assets.xcassets/Octicons/\(octicon.rawValue).symbolset/\(octicon.rawValue).svg")
    #expect(FileManager.default.fileExists(atPath: symbolset.standardizedFileURL.path))
  }

  @Test func labelsNameKindAndState() {
    #expect(StateGlyph(kind: .pullRequest, state: .draft).label == "Pull request, draft")
    #expect(StateGlyph(kind: .issue, state: .notPlanned).label == "Issue, not planned")
    #expect(StateGlyph(kind: .dependabotAlerts, state: .open, severity: .critical).label == "Dependabot alerts, critical")
    #expect(StateGlyph(kind: .release, state: nil).label == "Release")
  }
}
