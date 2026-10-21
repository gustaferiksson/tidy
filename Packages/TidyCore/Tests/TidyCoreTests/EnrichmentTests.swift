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
    #expect(server.requests.map(\.path).filter { $0 != "/graphql" } == ["/repos/octo/app/pulls/42"])
  }

  @Test func approvalReviewExplainsThePullRequestNotification() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: .json("graphql_timeline_review"))
    var thread = Fixture.thread("101")
    thread.subject.latestCommentURL = thread.subject.url
    let details = try await server.client.details(for: thread)
    let activity = try #require(details.activity)
    #expect(activity == Activity(
      actor: "octocat", kind: .reviewed(.approved), detail: "Ship it.\n\nNice work.",
      htmlURL: URL(string: "https://github.com/octo/app/pull/42#pullrequestreview-2")))
    #expect(activity.headline == "Approved by octocat")
    let item = InboxItem(thread: thread, status: .loaded(details))
    #expect(item.webURL == URL(string: "https://github.com/octo/app/pull/42#pullrequestreview-2"))
    #expect(item.previewMarkdown == "Adds **dark mode**.\n\n- [x] Tests")
    let query = try #require(server.requests.first { $0.path == "/graphql" }?.json?["query"] as? String)
    #expect(query.contains("viewer { login }"))
    #expect(!query.contains("on Team"), "a Team selection without read:org makes GitHub reject the whole query")
  }

  @Test func staleTrailingCommitsCollapseIntoOnePush() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: .json("graphql_timeline_push"))
    var thread = Fixture.thread("101")
    thread.subject.latestCommentURL = nil
    let activity = try #require(try await server.client.details(for: thread).activity)
    #expect(activity == Activity(actor: "Lisa Bot", kind: .pushed(commits: 3), detail: "Use system accent"))
    #expect(activity.headline == "Lisa Bot pushed 3 commits")
  }

  @Test func pushFillingTheTimelineWindowHasNoCount() async throws {
    let commit = #"{"type": "PullRequestCommit", "commit": {"committedDate": "2026-10-15T09:50:00Z", "messageHeadline": "Step", "author": {"name": "Hubot", "user": {"login": "hubot"}}}}"#
    let nodes = Array(repeating: commit, count: GitHubClient.timelineLimit).joined(separator: ",")
    let body = #"{"data": {"viewer": {"login": "mona"}, "repository": {"issueOrPullRequest": {"createdAt": "2026-10-01T08:00:00Z", "author": {"login": "hubot"}, "timelineItems": {"nodes": ["# + nodes + "]}}}}}"
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    let activity = try #require(try await server.client.details(for: Fixture.thread("101")).activity)
    #expect(activity.headline == "hubot pushed commits")
  }

  @Test func commitsFromBeforeThePullRequestWasOpenedAreNotAPush() async throws {
    let body = #"{"data": {"viewer": {"login": "hubot"}, "repository": {"issueOrPullRequest": {"createdAt": "2026-10-15T09:59:30Z", "author": {"login": "mona"}, "timelineItems": {"nodes": [{"type": "PullRequestCommit", "commit": {"committedDate": "2026-10-15T09:59:26Z", "messageHeadline": "Start", "author": {"name": "Mona", "user": {"login": "mona"}}}}]}}}}}"#
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    #expect(try await server.client.details(for: Fixture.thread("101")).activity == Activity(actor: "mona", kind: .opened))
  }

  @Test func reviewRequestForTheViewerWinsATimestampTie() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: .json("graphql_timeline_requested"))
    let activity = try #require(try await server.client.details(for: Fixture.thread("101")).activity)
    #expect(activity.kind == .requestedReview(from: "you"))
    #expect(activity.headline == "hubot requested your review")
  }

  @Test func mergeByTheViewerBeatsItsPairedClose() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("POST", "/graphql", respond: .json("graphql_timeline_merged"))
    let activity = try #require(try await server.client.details(for: Fixture.thread("101")).activity)
    #expect(activity == Activity(actor: "you", kind: .merged))
    #expect(activity.headline == "Merged by you")
  }

  @Test func recentlyOpenedIssueWithNothingElseNewIsOpened() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/issues/7", respond: .json("issue"))
    server.on("POST", "/graphql", respond: .json("graphql_timeline_issue"))
    let details = try await server.client.details(for: Fixture.thread("102"))
    #expect(details.activity == Activity(actor: "mona", kind: .opened))
    #expect(details.activity?.headline == "Opened by mona")
    var later = Fixture.thread("102")
    later.updatedAt = ISO8601DateFormatter().date(from: "2026-10-16T09:00:00Z")!
    #expect(try await server.client.details(for: later).activity == nil)
  }

  @Test func graphQLFailureLeavesActivityEmpty() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("GET", "/repos/octo/app/issues/comments/9001", respond: .json("comment"))
    server.on("POST", "/graphql") { _ in
      StubResponse(status: 200, body: Data(#"{"data": null, "errors": [{"type": "FORBIDDEN", "message": "no"}]}"#.utf8))
    }
    let details = try await server.client.details(for: Fixture.thread("101"))
    #expect(details.activity == nil)
    #expect(details.state == .draft)
    let item = InboxItem(thread: Fixture.thread("101"), status: .loaded(details))
    #expect(item.activity?.headline == "octocat commented")
    #expect(item.activity?.detail == "Looks good, one nit.\nSecond line.")
  }

  @Test func releaseIsPublishedByItsAuthor() async throws {
    let server = StubServer()
    server.on("GET", "/repos/octo/lib/releases/555", respond: .json("release"))
    let details = try await server.client.details(for: Fixture.thread("103"))
    #expect(details.activity?.headline == "Published by mona")
    #expect(server.requests.map(\.path) == ["/repos/octo/lib/releases/555"])
  }

  @Test(arguments: [
    (Activity.Kind.reviewed(.changesRequested), "Changes requested by hubot"),
    (.reviewed(.commented), "hubot commented"),
    (.commented, "hubot commented"),
    (.pushed(commits: 1), "hubot pushed a commit"),
    (.pushed(commits: 4), "hubot pushed 4 commits"),
    (.forcePushed, "hubot force-pushed"),
    (.requestedReview(from: "lisa"), "hubot requested review from lisa"),
    (.requestedReview(from: nil), "hubot requested a review"),
    (.assigned(to: "you"), "Assigned to you by hubot"),
    (.assigned(to: "lisa"), "Assigned to lisa by hubot"),
    (.closed, "Closed by hubot"),
    (.reopened, "Reopened by hubot"),
    (.readyForReview, "Marked ready for review by hubot"),
  ])
  func headlines(kind: Activity.Kind, headline: String) {
    #expect(Activity(actor: "hubot", kind: kind).headline == headline)
  }

  @Test func viewerLeadingAHeadlineIsCapitalised() {
    #expect(Activity(actor: "you", kind: .pushed(commits: 2)).headline == "You pushed 2 commits")
    #expect(Activity(actor: "you", kind: .closed).headline == "Closed by you")
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
    #expect(server.requests.filter { $0.path != "/graphql" }.count == 1)
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
