import Foundation
import Testing

@testable import TidyCore

struct GitHubClientTests {
  let since = Date(timeIntervalSince1970: 1_789_000_000)

  @Test func fetchesNotificationsWithHeaders() async throws {
    let server = StubServer()
    server.on(
      "GET", "/notifications",
      respond: .json(
        "notifications",
        headers: ["Last-Modified": "Thu, 15 Oct 2026 10:00:00 GMT", "X-Poll-Interval": "120", "X-OAuth-Scopes": "notifications, repo"]))
    let fetch = try await server.client.notifications(since: since, ifModifiedSince: nil)
    #expect(fetch.threads?.count == 8)
    #expect(fetch.isComplete)
    #expect(fetch.lastModified == "Thu, 15 Oct 2026 10:00:00 GMT")
    #expect(fetch.pollInterval == .seconds(120))
    #expect(fetch.scopes == ["notifications", "repo"])
    let request = try #require(server.requests.first)
    let query = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.contains(URLQueryItem(name: "all", value: "true")))
    #expect(query.contains(URLQueryItem(name: "per_page", value: "50")))
    #expect(query.contains(URLQueryItem(name: "since", value: since.formatted(.iso8601))))
    #expect(request.headers["Authorization"] == "Bearer \(server.token)")
    #expect(request.headers["If-Modified-Since"] == nil)
  }

  @Test func pollIntervalNeverDropsBelowSixtySeconds() async throws {
    let server = StubServer()
    server.on("GET", "/notifications", respond: .json("notifications", headers: ["X-Poll-Interval": "30"]))
    #expect(try await server.client.notifications(since: since, ifModifiedSince: nil).pollInterval == .seconds(60))
  }

  @Test func notModifiedEndsThePoll() async throws {
    let server = StubServer()
    server.on("GET", "/notifications", respond: StubResponse(status: 304, headers: ["X-Poll-Interval": "90"]))
    let fetch = try await server.client.notifications(since: since, ifModifiedSince: "Thu, 15 Oct 2026 10:00:00 GMT")
    #expect(fetch.threads == nil)
    #expect(fetch.pollInterval == .seconds(90))
    #expect(fetch.lastModified == "Thu, 15 Oct 2026 10:00:00 GMT")
    #expect(server.requests.count == 1)
    #expect(server.requests.first?.headers["If-Modified-Since"] == "Thu, 15 Oct 2026 10:00:00 GMT")
  }

  @Test func followsLinkHeaderUpToTwoHundredThreads() async throws {
    let server = StubServer()
    server.on("GET", "/notifications") { request in
      let page = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "page" }.flatMap { Int($0.value ?? "") } ?? 1
      let next = "<https://api.github.com/notifications?all=true&page=\(page + 1)>; rel=\"next\", <https://api.github.com/notifications?page=9>; rel=\"last\""
      return .encoded(makeThreads(count: 50, startingAt: (page - 1) * 50 + 1), headers: ["Link": next])
    }
    let fetch = try await server.client.notifications(since: since, ifModifiedSince: nil)
    #expect(fetch.threads?.count == 200)
    #expect(fetch.isComplete == false)
    #expect(server.requests.count == 4)
  }

  @Test func stopsPagingWithoutNextLink() async throws {
    let server = StubServer()
    server.on("GET", "/notifications") { request in
      let isSecond = request.url.query()?.contains("page=2") ?? false
      return isSecond
        ? .encoded(makeThreads(count: 10, startingAt: 51))
        : .encoded(makeThreads(count: 50), headers: ["Link": "<https://api.github.com/notifications?page=2>; rel=\"next\""])
    }
    let fetch = try await server.client.notifications(since: since, ifModifiedSince: nil)
    #expect(fetch.threads?.count == 60)
    #expect(fetch.isComplete)
  }

  @Test func neverSendsTheTokenToAnotherHost() async throws {
    let server = StubServer()
    server.on(
      "GET", "/notifications",
      respond: .encoded(makeThreads(count: 50), headers: ["Link": "<https://evil.example/notifications?page=2>; rel=\"next\""]))
    let fetch = try await server.client.notifications(since: since, ifModifiedSince: nil)
    #expect(fetch.threads?.count == 50)
    struct Pull: Decodable { let number: Int }
    await #expect(throws: GitHubError.forbidden) {
      try await server.client.get(Pull.self, from: URL(string: "https://evil.example/repos/octo/app/pulls/42")!)
    }
    await #expect(throws: GitHubError.forbidden) {
      try await server.client.get(Pull.self, from: URL(string: "http://api.github.com/repos/octo/app/pulls/42")!)
    }
    #expect(server.requests.allSatisfy { $0.url.host() == "api.github.com" && $0.url.scheme == "https" })
    #expect(server.requests.count == 1)
  }

  @Test func sinceIsLocalMidnightFourteenDaysAgo() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Stockholm")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15, minute: 42))!
    let expected = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2))!
    #expect(GitHubClient.since(now: now, calendar: calendar) == expected)
  }

  @Test func rejectsFineGrainedTokenBeforeAnyRequest() async {
    let server = StubServer()
    let client = GitHubClient(token: "github_pat_11ABC", session: server.session)
    await #expect(throws: GitHubError.fineGrainedToken) { try await client.validate() }
    #expect(server.requests.isEmpty)
  }

  @Test func validatesTokenScopes() async throws {
    let server = StubServer()
    server.on("GET", "/user", respond: .json("user", headers: ["X-OAuth-Scopes": "repo, notifications"]))
    let account = try await server.client.validate()
    #expect(account.user.login == "octocat")
    #expect(account.user.avatarURL == URL(string: "https://avatars.githubusercontent.com/u/1?v=4"))
    #expect(account.scopes == ["repo", "notifications"])
  }

  @Test func validationRequiresRepoScope() async {
    let server = StubServer()
    server.on("GET", "/user", respond: .json("user", headers: ["X-OAuth-Scopes": "notifications"]))
    await #expect(throws: GitHubError.missingScopes(["repo"])) { try await server.client.validate() }
  }

  @Test func classifiesTransportFailureAsOffline() async {
    let server = StubServer()
    server.on("GET", "/notifications", respond: .offline)
    await #expect(throws: GitHubError.offline) { try await server.client.notifications(since: since, ifModifiedSince: nil) }
  }

  @Test func classifiesUnauthorizedResponses() async {
    let server = StubServer()
    server.on("GET", "/notifications", respond: StubResponse(status: 401))
    await #expect(throws: GitHubError.unauthorized) { try await server.client.notifications(since: since, ifModifiedSince: nil) }
  }

  @Test func classifiesGarbageAsDecodingError() async {
    let server = StubServer()
    server.on("GET", "/notifications", respond: StubResponse(status: 200, body: Data("{".utf8)))
    await #expect(throws: GitHubError.decoding) { try await server.client.notifications(since: since, ifModifiedSince: nil) }
  }

  @Test func reusesCachedBodyOnETagMatch() async throws {
    let server = StubServer()
    let cache = ResponseCache(directory: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
    let client = GitHubClient(token: server.token, session: server.session, cache: cache)
    let url = URL(string: "https://api.github.com/repos/octo/app/pulls/42")!
    server.on("GET", "/repos/octo/app/pulls/42") { request in
      request.headers["If-None-Match"] == "\"abc\"" ? StubResponse(status: 304) : .json("pull", headers: ["ETag": "\"abc\""])
    }
    struct Pull: Decodable { let number: Int }
    #expect(try await client.get(Pull.self, from: url).number == 42)
    #expect(try await client.get(Pull.self, from: url).number == 42)
    #expect(server.requests.map { $0.headers["If-None-Match"] } == [nil, "\"abc\""])
  }

  @Test func sendsThreadActions() async throws {
    let server = StubServer()
    server.on("PATCH", "/notifications/threads/1", respond: StubResponse(status: 205))
    server.on("DELETE", "/notifications/threads/1", respond: StubResponse(status: 204))
    server.on("PUT", "/notifications/threads/1/subscription", respond: StubResponse(status: 200))
    server.on("PUT", "/notifications", respond: StubResponse(status: 202))
    server.on("PUT", "/repos/octo/app/notifications", respond: StubResponse(status: 205))
    let client = server.client
    let lastRead = Date(timeIntervalSince1970: 1_790_000_000)
    try await client.markRead(threadID: "1")
    try await client.remove(threadID: "1")
    try await client.mute(threadID: "1")
    try await client.unmute(threadID: "1")
    try await client.markAllRead(lastReadAt: lastRead)
    try await client.markAllRead(lastReadAt: lastRead, repository: "octo/app")
    let requests = server.requests
    #expect(requests.map { "\($0.method) \($0.path)" } == [
      "PATCH /notifications/threads/1", "DELETE /notifications/threads/1",
      "PUT /notifications/threads/1/subscription", "PUT /notifications/threads/1/subscription",
      "PUT /notifications", "PUT /repos/octo/app/notifications",
    ])
    #expect(requests[2].json?["ignored"] as? Bool == true)
    #expect(requests[3].json?["ignored"] as? Bool == false)
    #expect(requests[4].json?["last_read_at"] as? String == "2026-09-21T14:13:20Z")
  }
}

struct ErrorClassificationTests {
  let now = Date(timeIntervalSince1970: 1_790_000_000)

  func response(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://api.github.com/x")!, statusCode: status, httpVersion: nil, headerFields: headers)!
  }

  @Test func successAndNotModifiedAreNotErrors() {
    #expect(GitHubError.classify(response(200)) == nil)
    #expect(GitHubError.classify(response(205)) == nil)
    #expect(GitHubError.classify(response(304)) == nil)
  }

  @Test func rateLimitUsesResetHeader() {
    let error = GitHubError.classify(response(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1790003600"]), now: now)
    #expect(error == .rateLimited(resetsAt: Date(timeIntervalSince1970: 1_790_003_600)))
  }

  @Test func rateLimitUsesRetryAfter() {
    #expect(GitHubError.classify(response(429, ["Retry-After": "30"]), now: now) == .rateLimited(resetsAt: now.addingTimeInterval(30)))
    #expect(GitHubError.classify(response(403, ["Retry-After": "120"]), now: now) == .rateLimited(resetsAt: now.addingTimeInterval(120)))
  }

  @Test func ssoRequiredParsesOrganization() {
    let header = "required; url=https://github.com/orgs/acme/sso?authorization_request=AbC123"
    #expect(
      GitHubError.classify(response(403, ["X-GitHub-SSO": header]))
        == .ssoRequired(organization: "acme", url: URL(string: "https://github.com/orgs/acme/sso?authorization_request=AbC123")))
  }

  @Test func plainForbiddenAndOthers() {
    #expect(GitHubError.classify(response(403)) == .forbidden)
    #expect(GitHubError.classify(response(401)) == .unauthorized)
    #expect(GitHubError.classify(response(404)) == .notFound)
    #expect(GitHubError.classify(response(502)) == .server(status: 502))
    #expect(GitHubError.classify(response(422)) == .unexpectedStatus(422))
  }
}
