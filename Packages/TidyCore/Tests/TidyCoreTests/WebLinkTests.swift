import Foundation
import Testing

@testable import TidyCore

struct WebLinkTests {
  @Test(arguments: [
    ("https://api.github.com/repos/o/r/pulls/12", "https://github.com/o/r/pull/12"),
    ("https://api.github.com/repos/o/r/issues/7", "https://github.com/o/r/issues/7"),
    ("https://api.github.com/repos/o/r/commits/a1b2c3", "https://github.com/o/r/commit/a1b2c3"),
    ("https://api.github.com/repos/o/r/discussions/3", "https://github.com/o/r/discussions/3"),
  ])
  func convertsAPIURLs(api: String, web: String) {
    #expect(WebLink.webURL(forAPI: URL(string: api)!) == URL(string: web))
  }

  @Test(arguments: [
    "https://api.github.com/repos/o/r/releases/555",
    "https://api.github.com/repos/o/r/pulls/12/comments",
    "https://example.com/repos/o/r/pulls/12",
    "https://api.github.com/users/octocat",
  ])
  func refusesURLsItCannotMap(api: String) {
    #expect(WebLink.webURL(forAPI: URL(string: api)!) == nil)
  }

  @Test(arguments: [
    ("https://api.github.com/repos/o/r/issues/comments/9001", "issuecomment-9001"),
    ("https://api.github.com/repos/o/r/pulls/comments/77", "discussion_r77"),
    ("https://api.github.com/repos/o/r/comments/321", "commitcomment-321"),
  ])
  func derivesCommentAnchors(api: String, anchor: String) {
    #expect(WebLink.anchor(forCommentAPI: URL(string: api)!) == anchor)
  }

  @Test func pullRequestLinksToLatestComment() {
    #expect(
      WebLink.url(for: Fixture.thread("101"), details: nil)
        == URL(string: "https://github.com/octo/app/pull/42#issuecomment-9001"))
  }

  @Test func latestCommentEqualToSubjectHasNoAnchor() {
    #expect(WebLink.url(for: Fixture.thread("102"), details: nil) == URL(string: "https://github.com/octo/app/issues/7"))
  }

  @Test func commitLinksToCommitComment() {
    #expect(
      WebLink.url(for: Fixture.thread("107"), details: nil)
        == URL(string: "https://github.com/octo/lib/commit/a1b2c3d4#commitcomment-321"))
  }

  @Test func releaseFallsBackToReleasesPageUntilFetched() {
    let release = Fixture.thread("103")
    #expect(WebLink.url(for: release, details: nil) == URL(string: "https://github.com/octo/lib/releases"))
    let fetched = SubjectDetails(htmlURL: URL(string: "https://github.com/octo/lib/releases/tag/v2.0.0"))
    #expect(WebLink.url(for: release, details: fetched) == URL(string: "https://github.com/octo/lib/releases/tag/v2.0.0"))
  }

  @Test func fetchedCommentURLWins() {
    let comment = Comment(
      apiURL: URL(string: "https://api.github.com/repos/octo/app/issues/comments/9001")!, author: nil, body: "",
      htmlURL: URL(string: "https://github.com/octo/app/pull/42#issuecomment-9001"))
    #expect(
      WebLink.url(for: Fixture.thread("101"), details: SubjectDetails(latestComment: comment))
        == URL(string: "https://github.com/octo/app/pull/42#issuecomment-9001"))
  }

  @Test(arguments: [
    ("104", "https://github.com/octo/app/actions"),
    ("105", "https://github.com/octo/app/security/dependabot"),
    ("106", "https://github.com/octo/lib"),
    ("108", "https://github.com/octo/app/discussions"),
  ])
  func nullSubjectURLFallsBack(id: String, web: String) {
    #expect(WebLink.url(for: Fixture.thread(id), details: nil) == URL(string: web))
  }

  @Test func securityFallbacks() {
    let repo = URL(string: "https://github.com/o/r")!
    #expect(WebLink.fallback(for: .secretScanningAlert, repository: repo) == URL(string: "https://github.com/o/r/security/secret-scanning"))
    #expect(WebLink.fallback(for: .workflowRun, repository: repo) == URL(string: "https://github.com/o/r/actions"))
  }
}
