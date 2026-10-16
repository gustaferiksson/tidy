import Foundation
import Testing

@testable import TidyCore

struct ModelTests {
  @Test func decodesEveryFixtureThreadIncludingUnknownTypes() {
    let threads = Fixture.threads
    #expect(threads.map(\.id) == ["101", "102", "103", "104", "105", "106", "107", "108"])
    #expect(
      threads.map(\.subject.kind) == [
        .pullRequest, .issue, .release, .checkSuite, .dependabotAlerts, .unknown("HoloDeckSession"), .commit, .discussion,
      ])
  }

  @Test func decodesThreadFields() {
    let pull = Fixture.thread("101")
    #expect(pull.reason == .reviewRequested)
    #expect(pull.unread)
    #expect(pull.lastReadAt == nil)
    #expect(pull.updatedAt == ISO8601DateFormatter().date(from: "2026-10-15T10:00:00Z"))
    #expect(pull.subject.url == URL(string: "https://api.github.com/repos/octo/app/pulls/42"))
    #expect(pull.subject.latestCommentURL == URL(string: "https://api.github.com/repos/octo/app/issues/comments/9001"))
    #expect(pull.repository.fullName == "octo/app")
    #expect(pull.repository.owner.login == "octo")
    #expect(pull.repository.isPrivate == false)
    #expect(pull.repository.htmlURL == URL(string: "https://github.com/octo/app"))
    #expect(pull.number == 42)
    #expect(Fixture.thread("103").repository.isPrivate)
    #expect(Fixture.thread("102").lastReadAt != nil)
  }

  @Test func keepsUnknownReasonsAndKinds() throws {
    let unknown = Fixture.thread("106")
    #expect(unknown.reason.rawValue == "brand_new_reason")
    #expect(unknown.reason.title == "Brand new reason")
    #expect(unknown.reason.group == .participating)
    let roundTrip = try GitHubClient.decoder.decode(
      NotificationThread.self, from: GitHubClient.encoder.encode(unknown))
    #expect(roundTrip == unknown)
  }

  @Test func mapsLegacyVulnerabilityAlertToDependabot() {
    #expect(SubjectKind(rawValue: "RepositoryVulnerabilityAlert") == .dependabotAlerts)
  }

  @Test(arguments: [
    ("CI workflow run failed for main branch", SubjectState.failed),
    ("Deploy workflow run succeeded for main branch", .succeeded),
    ("Lint workflow run cancelled for feature branch", .cancelled),
  ])
  func readsCIStateFromTitle(title: String, state: SubjectState) {
    var thread = Fixture.thread("104")
    thread.subject.title = title
    #expect(thread.ciState == state)
  }

  @Test func ciStateIsOnlyForCIKinds() {
    var thread = Fixture.thread("101")
    thread.subject.title = "Build failed"
    #expect(thread.ciState == nil)
  }

  @Test func severityAcceptsMediumAndModerate() {
    #expect(Severity(apiValue: "medium") == .moderate)
    #expect(Severity(apiValue: "MODERATE") == .moderate)
    #expect(Severity(apiValue: "unknown") == nil)
    #expect(Severity.critical > .high && Severity.high > .moderate && Severity.moderate > .low)
  }

  @Test func groupsKnownReasons() {
    #expect(ReasonGroup.security.reasons == [.securityAlert, .securityAdvisoryCredit])
    #expect(ReasonGroup.participating.reasons.contains(.reviewRequested))
    #expect(ReasonGroup.activity.reasons.contains(.subscribed))
    #expect(Reason.reviewRequested.title == "Review requested")
  }
}
