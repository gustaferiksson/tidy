import Foundation
import Testing

@testable import TidyCore

struct ThreadDetailsTests {
  static let scopes = ["notifications", "repo", "read:org"]

  @Test func requestIsOneGraphQLPostWithVariables() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    _ = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    #expect(server.requests.count == 1)
    let request = try #require(server.requests.first)
    #expect(request.url.host() == "api.github.com")
    #expect(request.headers["Authorization"] == "Bearer \(server.token)")
    let variables = try #require(request.json?["variables"] as? [String: Any])
    #expect(variables["owner"] as? String == "octo")
    #expect(variables["name"] as? String == "app")
    #expect(variables["number"] as? Int == 42)
    let query = try #require(request.json?["query"] as? String)
    #expect(query.contains("issueOrPullRequest(number: $number)"))
    #expect(query.contains("statusCheckRollup"))
  }

  @Test func decodesPullRequest() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    let details = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    #expect(details.author == GitHubUser(login: "mona", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?s=40&v=4")))
    #expect(details.body == "Adds **dark mode**.")
    #expect(details.labels == [IssueLabel(name: "enhancement", color: "a2eeef"), IssueLabel(name: "ui", color: "ededed")])
    #expect(details.assignees.map(\.login) == ["mona"])
    #expect(details.milestone == "v1.2")
    let pull = try #require(details.pullRequest)
    #expect(pull.baseBranch == "main")
    #expect(pull.headBranch == "mona/dark-mode")
    #expect([pull.additions, pull.deletions, pull.changedFiles] as [Int] == [120, 14, 7])
    #expect(pull.hasConflicts)
    #expect(pull.reviewDecision == .changesRequested)
    #expect(pull.reviewers.map(\.user.login) == ["octocat", "hubot", "lisa", "design"], "the author's own review is not a reviewer")
    #expect(pull.reviewers.map(\.state) == [.approved, .changesRequested, .requested, .requested])
    let checks = try #require(pull.checks)
    #expect(checks.state == .failure)
    #expect(checks.passed == 3)
    #expect(checks.failing == ["lint"])
    #expect(checks.pending == ["deploy-preview"])
    #expect(checks.summary == "3 checks passed · 1 failing: lint · 1 pending")
    #expect(details.comments.map(\.id) == ["IC_1", "PRR_1", "PRR_3"])
    #expect(details.comments.map(\.review) == [nil, .approved, .changesRequested])
    #expect(details.comments.last?.author?.login == "hubot")
    #expect(details.comments.first?.url == URL(string: "https://github.com/octo/app/pull/42#issuecomment-1"))
    #expect(details.totalComments == 14)
    #expect(details.discussion == nil)
  }

  @Test func teamReviewersAreQueriedOnlyWithReadOrg() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    _ = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: ["notifications", "repo"])
    _ = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    let queries = server.requests.compactMap { $0.json?["query"] as? String }
    #expect(queries.count == 2)
    #expect(!queries[0].contains("on Team"), "a Team selection without read:org makes GitHub reject the whole query")
    #expect(queries[1].contains("... on Team { slug avatarUrl(size: 40) }"))
  }

  @Test func requestedUserAndTeamApprovedAndChangesRequested() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    let pull = try #require(try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes).pullRequest)
    let states = Dictionary(uniqueKeysWithValues: pull.reviewers.map { ($0.user.login, $0.state) })
    #expect(states == ["octocat": .approved, "hubot": .changesRequested, "lisa": .requested, "design": .requested])
  }

  @Test func recordedCommentedReviewWithPendingRequest() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull_commented"))
    let details = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    let pull = try #require(details.pullRequest)
    #expect(pull.reviewDecision == nil)
    #expect(pull.reviewers == [
      Reviewer(user: GitHubUser(login: "mona", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/2?s=40&v=4")), state: .commented),
      Reviewer(user: GitHubUser(login: "octocat", avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1?s=40&v=4")), state: .requested),
    ])
    #expect(details.comments.map(\.review) == [.commented])
    #expect(details.totalComments == 1)
  }

  @Test func recordedReRequestedReviewerIsPendingAgain() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_pull_rerequested"))
    let details = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    let pull = try #require(details.pullRequest)
    #expect(pull.reviewDecision == .approved)
    #expect(pull.reviewers.map(\.user.login) == ["octocat", "hubot"])
    #expect(pull.reviewers.map(\.state) == [.approved, .requested])
    #expect(details.comments.map(\.author?.login) == ["hubot", "octocat"])
    #expect(details.comments.map(\.review) == [.commented, .approved])
    #expect(details.totalComments == 2)
  }

  @Test func partialErrorsAndMalformedNodesKeepTheRest() async throws {
    let server = StubServer()
    let body = #"""
      {"data":{"repository":{"issueOrPullRequest":{"kind":"PullRequest","baseRefName":"main","headRefName":"f",
        "latestReviews":{"nodes":[{"state":"APPROVED","author":{"login":"octocat"}},null,{"state":7,"author":{"login":"bad"}}]},
        "reviewRequests":{"nodes":[{"requestedReviewer":null},{"requestedReviewer":{"login":"hubot"}}]},
        "timelineItems":{"filteredCount":3,"nodes":[{"id":"IC_1","body":"hi","createdAt":"yesterday"},{"id":"IC_2","body":"ok","createdAt":"2026-10-15T09:00:00Z"}]}
      }}},
      "errors":[{"type":"FORBIDDEN","path":["repository","issueOrPullRequest","reviewRequests","nodes",0,"requestedReviewer"],"message":"Resource not accessible"}]}
      """#
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    let details = try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes)
    let pull = try #require(details.pullRequest)
    #expect(pull.reviewers.map(\.user.login) == ["octocat", "hubot"])
    #expect(pull.reviewers.map(\.state) == [.approved, .requested])
    #expect(details.comments.map(\.id) == ["IC_2"])
    #expect(details.totalComments == 3)
  }

  @Test func decodesIssue() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: .json("graphql_issue"))
    let details = try await server.client.threadDetails(for: Fixture.thread("102"), scopes: Self.scopes)
    #expect(server.requests.first?.json?["variables"].flatMap { $0 as? [String: Any] }?["number"] as? Int == 7)
    #expect(details.pullRequest == nil)
    #expect(details.labels.map(\.name) == ["bug"])
    #expect(details.milestone == nil)
    #expect(details.comments.map(\.body) == ["Can't reproduce.", "Same here."])
    #expect(details.comments.last?.author == nil)
    #expect(details.totalComments == 2)
  }

  @Test func discussionSearchesByTitleAndMatchesExactly() async throws {
    let server = StubServer()
    let body = #"""
      {"data":{"search":{"nodes":[
        {"kind":"Discussion","title":"How do I configure themes? (old)","body":"no","comments":{"totalCount":0,"nodes":[]}},
        {},
        {"kind":"Discussion","title":"How do I configure themes?","body":"yes","isAnswered":true,"category":{"name":"Q&A"},
         "comments":{"totalCount":1,"nodes":[{"id":"DC_1","body":"Use Settings.","createdAt":"2026-10-15T09:00:00Z","isAnswer":true}]}}
      ]}}}
      """#
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    let details = try await server.client.threadDetails(for: Fixture.thread("108"), scopes: Self.scopes)
    let variables = server.requests.first?.json?["variables"] as? [String: Any]
    #expect(variables?["query"] as? String == #"repo:octo/app in:title "How do I configure themes?""#)
    #expect(details.body == "yes")
    #expect(details.discussion == DiscussionDetails(category: "Q&A", isAnswered: true))
    #expect(details.comments.first?.isAnswer == true)
  }

  @Test func missingNodeIsNotFound() async throws {
    let server = StubServer()
    let body = #"{"data":{"repository":{"issueOrPullRequest":null}},"errors":[{"type":"NOT_FOUND","message":"x"}]}"#
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    await #expect(throws: GitHubError.notFound) { try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes) }
  }

  @Test func forbiddenAndSchemaErrors() async throws {
    let server = StubServer()
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(#"{"data":{"repository":null},"errors":[{"type":"FORBIDDEN"}]}"#.utf8)))
    await #expect(throws: GitHubError.forbidden) { try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes) }
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(#"{"errors":[{"message":"Field 'x' doesn't exist"}]}"#.utf8)))
    await #expect(throws: GitHubError.decoding) { try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes) }
    server.on("POST", "/graphql", respond: StubResponse(status: 502))
    await #expect(throws: GitHubError.server(status: 502)) { try await server.client.threadDetails(for: Fixture.thread("101"), scopes: Self.scopes) }
  }

  @Test func discussionWithoutScopeIsNotFound() async throws {
    let server = StubServer()
    let body = #"{"data":{"search":null},"errors":[{"type":"INSUFFICIENT_SCOPES","message":"read:discussion"}]}"#
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(body.utf8)))
    await #expect(throws: GitHubError.notFound) { try await server.client.threadDetails(for: Fixture.thread("108"), scopes: Self.scopes) }
  }

  @Test func unsupportedThreadsAreNotFetched() {
    #expect(ThreadDetails.isSupported(Fixture.thread("101")))
    #expect(ThreadDetails.isSupported(Fixture.thread("108")))
    #expect(!ThreadDetails.isSupported(Fixture.thread("103")))
    #expect(!ThreadDetails.isSupported(Fixture.thread("105")))
  }

  @Test func checkSummaryWording() {
    #expect(CheckSummary(state: .success, passed: 1).summary == "1 check passed")
    #expect(CheckSummary(state: .failure, passed: 0, failing: ["a", "b", "c", "d", "e"]).summary == "5 failing: a, b, c +2")
    #expect(CheckSummary(state: .pending, passed: 0).summary == "No checks reported")
  }
}

@MainActor
struct ThreadDetailsStoreTests {
  let server = StubServer()
  let threads = Locked(Fixture.threads)

  init() {
    server.on("GET", "/notifications") { [threads] _ in
      .encoded(threads.withLock { $0 }, headers: ["X-OAuth-Scopes": "repo, notifications"])
    }
  }

  func makeStore() async -> InboxStore {
    let store = InboxStore(
      directory: FileManager.default.temporaryDirectory.appending(path: "TidyTests-\(UUID().uuidString)"),
      tokenStorage: MemoryTokenStorage(server.token), session: server.session,
      networkPaths: AsyncStream { _ in })
    await store.refresh()
    return store
  }

  func graphQLRequests() -> Int {
    server.requests.count { $0.path == "/graphql" }
  }

  func waitForLoad(_ store: InboxStore, _ id: String) async throws -> ThreadDetailsStatus? {
    for _ in 0..<100 {
      let item = try #require(store.inbox.first { $0.id == id })
      if let status = store.threadDetails(for: item), status != .loading { return status }
      try await Task.sleep(for: .milliseconds(10))
    }
    return nil
  }

  @Test func pollingNeverFetchesThreadDetails() async throws {
    _ = await makeStore()
    try await Task.sleep(for: .milliseconds(100))
    #expect(graphQLRequests() == 0)
  }

  @Test func cachedUntilUpdatedAtChanges() async throws {
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    let store = await makeStore()
    store.loadThreadDetails(for: "101")
    store.loadThreadDetails(for: "101")
    #expect(try await waitForLoad(store, "101")?.details?.pullRequest?.headBranch == "mona/dark-mode")
    store.loadThreadDetails(for: "101")
    try await Task.sleep(for: .milliseconds(50))
    #expect(graphQLRequests() == 1)

    threads.withLock { $0[0].updatedAt.addTimeInterval(60) }
    await store.refresh()
    let item = try #require(store.inbox.first { $0.id == "101" })
    #expect(store.threadDetails(for: item) == nil)
    store.loadThreadDetails(for: "101")
    _ = try await waitForLoad(store, "101")
    #expect(graphQLRequests() == 2)
  }

  @Test func failureRetriesAndNotFoundIsUnavailable() async throws {
    server.on("POST", "/graphql", respond: StubResponse(status: 500))
    let store = await makeStore()
    store.loadThreadDetails(for: "102")
    #expect(try await waitForLoad(store, "102") == .failed)
    server.on("POST", "/graphql", respond: StubResponse(status: 200, body: Data(#"{"data":{"repository":null}}"#.utf8)))
    store.loadThreadDetails(for: "102")
    #expect(try await waitForLoad(store, "102") == .unavailable)
    store.loadThreadDetails(for: "102")
    try await Task.sleep(for: .milliseconds(50))
    #expect(graphQLRequests() == 2)
  }

  @Test func unsupportedKindsAndDisconnectClearCache() async throws {
    server.on("POST", "/graphql", respond: .json("graphql_pull"))
    let store = await makeStore()
    store.loadThreadDetails(for: "103")
    store.loadThreadDetails(for: "101")
    _ = try await waitForLoad(store, "101")
    #expect(graphQLRequests() == 1)
    let item = try #require(store.inbox.first { $0.id == "101" })
    store.disconnect()
    #expect(store.threadDetails(for: item) == nil)
  }}
