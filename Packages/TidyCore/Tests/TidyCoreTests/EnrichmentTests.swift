import Foundation
import Testing

@testable import TidyCore

struct EnrichmentTests {
  @Test func pullRequestDraftWithLatestComment() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("GET", "/repos/octo/app/issues/comments/9001", respond: .json("comment"))
    let details = try await server.client.details(for: Fixture.thread("101"))
    #expect(details.state == .draft)
    #expect(details.author?.login == "mona")
    #expect(details.body == "Adds **dark mode**.\n\n- [x] Tests")
    #expect(details.htmlURL == URL(string: "https://github.com/octo/app/pull/42"))
    #expect(details.latestComment?.author?.login == "octocat")
    #expect(details.latestComment?.body == "Looks good, one nit.\nSecond line.")
    let item = InboxItem(thread: Fixture.thread("101"), status: .loaded(details))
    #expect(item.glyph == StateGlyph(kind: .pullRequest, state: .draft))
    #expect(item.webURL == URL(string: "https://github.com/octo/app/pull/42#issuecomment-9001"))
    #expect(item.previewMarkdown == "Looks good, one nit.\nSecond line.")
  }

  @Test func reusesCommentWhenURLUnchanged() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    let previous = SubjectDetails(
      latestComment: Comment(
        apiURL: URL(string: "https://api.github.com/repos/octo/app/issues/comments/9001")!, author: nil, body: "cached",
        htmlURL: nil))
    let details = try await server.client.details(for: Fixture.thread("101"), previous: previous)
    #expect(details.latestComment?.body == "cached")
    #expect(server.requests.map(\.path) == ["/repos/octo/app/pulls/42"])
  }

  @Test func mergedAndClosedPullRequests() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42") { _ in
      StubResponse(status: 200, body: Data(#"{"state":"closed","merged":true,"draft":false}"#.utf8))
    }
    server.on("GET", "/repos/octo/app/issues/comments/9001", respond: .json("comment"))
    #expect(try await server.client.details(for: Fixture.thread("101")).state == .merged)
    server.on("GET", "/repos/octo/app/pulls/42") { _ in
      StubResponse(status: 200, body: Data(#"{"state":"closed","merged":false,"draft":false}"#.utf8))
    }
    #expect(try await server.client.details(for: Fixture.thread("101")).state == .closed)
  }

  @Test func issueClosedAsNotPlannedSkipsSelfComment() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/issues/7", respond: .json("issue"))
    let details = try await server.client.details(for: Fixture.thread("102"))
    #expect(details.state == .notPlanned)
    #expect(details.latestComment == nil)
    #expect(server.requests.count == 1)
  }

  @Test func releaseUsesFetchedHTMLURL() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/lib/releases/555", respond: .json("release"))
    let item = InboxItem(thread: Fixture.thread("103"), status: .loaded(try await server.client.details(for: Fixture.thread("103"))))
    #expect(item.webURL == URL(string: "https://github.com/octo/lib/releases/tag/v2.0.0"))
    #expect(item.author?.login == "mona")
  }

  @Test func dependabotSummarisesOpenAlerts() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/dependabot/alerts", respond: .json("dependabot_alerts"))
    let details = try await server.client.details(for: Fixture.thread("105"))
    #expect(server.requests.first?.url.query()?.contains("state=open") == true)
    #expect(details.alerts.map(\.package) == ["lodash", "requests", "minimist"])
    #expect(details.alerts.map(\.severity) == [.critical, .moderate, .critical])
    #expect(details.alerts.first?.advisoryID == "GHSA-aaaa-bbbb-cccc")
    #expect(details.highestSeverity == .critical)
    let item = InboxItem(thread: Fixture.thread("105"), status: .loaded(details))
    #expect(item.title == "3 vulnerable dependencies · 2 critical")
    #expect(item.glyph.tone == .red)
    #expect(item.webURL == URL(string: "https://github.com/octo/app/security/dependabot"))
  }

  @Test func dependabotForbiddenFallsBackToGreyGlyph() async {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/dependabot/alerts", respond: StubResponse(status: 403))
    await #expect(throws: GitHubError.forbidden) { try await server.client.details(for: Fixture.thread("105")) }
    let item = InboxItem(thread: Fixture.thread("105"), status: .failed)
    #expect(item.glyph.tone == .grey)
    #expect(item.title == "Your repository has dependencies with security vulnerabilities")
  }

  @Test func subjectsWithoutURLNeedNoRequest() async throws {
    let server = StubServer()
    #expect(try await server.client.details(for: Fixture.thread("108")).state == .open)
    #expect(try await server.client.details(for: Fixture.thread("104")).state == nil)
    #expect(server.requests.isEmpty)
    #expect(InboxItem(thread: Fixture.thread("104")).glyph.octicon == .xCircle)
  }
}
