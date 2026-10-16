import Foundation
import Synchronization
import Testing

@testable import TidyCore

final class MemoryTokenStorage: TokenStorage {
  private let token: Mutex<String?>

  init(_ token: String?) {
    self.token = Mutex(token)
  }

  func read() -> String? { token.withLock { $0 } }
  func save(_ token: String) throws { self.token.withLock { $0 = token } }
  func delete() throws { token.withLock { $0 = nil } }
}

final class FlakyKeychain: TokenStorage {
  private let failures: Mutex<Int>
  let token: String

  init(token: String, failures: Int) {
    self.token = token
    self.failures = Mutex(failures)
  }

  func read() throws -> String? {
    let failing = failures.withLock { count in
      defer { count -= 1 }
      return count > 0
    }
    if failing { throw KeychainError(status: errSecInteractionNotAllowed) }
    return token
  }

  func save(_ token: String) throws {}
  func delete() throws {}
}

final class EventRecorder: Sendable {
  private let events = Locked<[InboxEvent]>([])

  @MainActor init(_ store: InboxStore) {
    let stream = store.events
    Task { [events] in
      for await event in stream { events.withLock { $0.append(event) } }
    }
  }

  func all() async -> [InboxEvent] {
    try? await Task.sleep(for: .milliseconds(50))
    return events.withLock { recorded in
      defer { recorded.removeAll() }
      return recorded
    }
  }

  func banners() async -> [InboxEvent] {
    try? await Task.sleep(for: .milliseconds(50))
    return events.withLock { recorded in
      defer { recorded.removeAll() }
      return recorded.filter { if case .withdraw = $0 { false } else { true } }
    }
  }
}

@MainActor
struct InboxStoreTests {
  nonisolated static let now = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
  let server = StubServer()
  let threads: Locked<[NotificationThread]>
  let directory = FileManager.default.temporaryDirectory.appending(path: "TidyTests-\(UUID().uuidString)")

  init() {
    let threads = Locked(Fixture.threads)
    self.threads = threads
    server.on("GET", "/notifications") { [threads] _ in
      .encoded(threads.withLock { $0 }, headers: ["X-OAuth-Scopes": "repo, notifications", "Last-Modified": "Thu, 15 Oct 2026 10:00:00 GMT"])
    }
    for id in 101...108 {
      server.on("PATCH", "/notifications/threads/\(id)", respond: StubResponse(status: 205))
      server.on("DELETE", "/notifications/threads/\(id)", respond: StubResponse(status: 204))
    }
  }

  func makeStore(commitDelay: Duration = .seconds(60)) -> InboxStore {
    InboxStore(
      directory: directory, tokenStorage: MemoryTokenStorage(server.token), session: server.session,
      commitDelay: commitDelay, bannerWait: .milliseconds(200), networkPaths: AsyncStream { _ in },
      now: { Self.now })
  }

  func addThread(_ id: String, minutesAfterNewest minutes: Double = 10, unread: Bool = true, reason: Reason = .mention) {
    let template = Fixture.thread("102")
    let thread = NotificationThread(
      id: id, reason: reason, unread: unread,
      updatedAt: Fixture.thread("101").updatedAt.addingTimeInterval(minutes * 60),
      subject: Subject(title: "New \(id)", kind: .unknown("Novel")), repository: template.repository)
    threads.withLock { $0.insert(thread, at: 0) }
  }

  func requests(_ method: String) -> [String] {
    server.requests.filter { $0.method == method }.map(\.path)
  }

  @Test func firstFetchIsBaselineOnly() async {
    let store = makeStore()
    let recorder = EventRecorder(store)
    await store.refresh()
    #expect(store.inbox.count == 8)
    #expect(store.hasLoaded)
    #expect(store.lastSync == Self.now)
    #expect(await recorder.banners().isEmpty)
    addThread("201")
    await store.refresh()
    let banners = await recorder.banners()
    #expect(banners.count == 1)
    guard case .newThread(let item) = banners.first else { return #expect(Bool(false)) }
    #expect(item.id == "201")
  }

  @Test func threadsReadOnGitHubWithdrawTheirBanners() async {
    let store = makeStore()
    let recorder = EventRecorder(store)
    await store.refresh()
    #expect(await recorder.all().isEmpty)
    threads.withLock { list in
      for index in list.indices where ["101", "103"].contains(list[index].id) { list[index].unread = false }
    }
    await store.refresh()
    #expect(await recorder.all() == [.withdraw(threadIDs: ["101", "103"])])
  }

  @Test func moreThanFiveNewThreadsSendOneSummary() async {
    let store = makeStore()
    let recorder = EventRecorder(store)
    await store.refresh()
    for index in 1...6 { addThread("30\(index)", minutesAfterNewest: Double(index)) }
    await store.refresh()
    #expect(await recorder.banners() == [.summary(count: 6)])
  }

  @Test func exactlyFiveNewThreadsSendIndividualBanners() async {
    let store = makeStore()
    let recorder = EventRecorder(store)
    await store.refresh()
    for index in 1...5 { addThread("30\(index)", minutesAfterNewest: Double(index)) }
    await store.refresh()
    #expect(await recorder.banners().count == 5)
  }

  @Test func readSilencedAndFilteredThreadsDoNotNotify() async {
    let store = makeStore()
    let recorder = EventRecorder(store)
    store.silencedReasons = [.subscribed]
    store.rules = [FilterRule(conditions: [.reason(.teamMention)], action: .dontNotify)]
    await store.refresh()
    addThread("401", unread: false)
    addThread("402", reason: .subscribed)
    addThread("403", reason: .teamMention)
    addThread("404", reason: .assign)
    await store.refresh()
    let banners = await recorder.banners()
    #expect(banners.count == 1)
    guard case .newThread(let item) = banners.first else { return #expect(Bool(false)) }
    #expect(item.id == "404")
    #expect(store.inbox.contains { $0.id == "403" })
  }

  @Test func tokenChangeResetsBaseline() async throws {
    server.on("GET", "/user", respond: .json("user", headers: ["X-OAuth-Scopes": "repo"]))
    let store = makeStore()
    let recorder = EventRecorder(store)
    await store.refresh()
    try await store.connect(token: server.token)
    #expect(store.account?.user.login == "octocat")
    addThread("501")
    await store.refresh()
    #expect(await recorder.banners().isEmpty)
    #expect(store.inbox.contains { $0.id == "501" })
  }

  @Test func missingAccountIsFilledOnNextPoll() async throws {
    server.on("GET", "/user", respond: .json("user", headers: ["X-OAuth-Scopes": "repo"]))
    let store = makeStore()
    #expect(store.account == nil)
    await store.refresh()
    #expect(store.account?.user.login == "octocat")
    #expect(makeStore().account?.user.login == "octocat")
  }

  @Test func keychainReadErrorIsAnIssueNotASignOut() async {
    let store = InboxStore(
      directory: directory, tokenStorage: FlakyKeychain(token: server.token, failures: 2), session: server.session,
      networkPaths: AsyncStream { _ in }, now: { Self.now })
    #expect(store.isSignedIn)
    #expect(store.issue == .keychainUnavailable)
    #expect(await store.refresh() == .seconds(60))
    #expect(store.issue == .keychainUnavailable)
    #expect(store.isSignedIn)
    await store.refresh()
    #expect(store.issue == nil)
    #expect(store.inbox.count == 8)
  }

  @Test func connectRejectsFineGrainedTokens() async {
    let store = makeStore()
    await #expect(throws: GitHubError.fineGrainedToken) { try await store.connect(token: "github_pat_abc") }
    #expect(server.requests.isEmpty)
  }

  @Test func conditionalPollReturningOnlyChangedThreadsKeepsTheRest() async {
    server.on("GET", "/notifications") { [threads] request in
      let all = threads.withLock { $0 }
      let changed = request.headers["If-Modified-Since"].map { _ in all.filter { $0.id.hasPrefix("7") } } ?? all
      return .encoded(changed, headers: ["X-OAuth-Scopes": "repo", "Last-Modified": "Thu, 15 Oct 2026 10:00:00 GMT"])
    }
    let store = makeStore()
    await store.refresh()
    #expect(store.inbox.count == 8)
    addThread("701")
    addThread("702", minutesAfterNewest: 11)
    await store.refresh()
    #expect(store.inbox.count == 10)
    let polls = server.requests.filter { $0.path == "/notifications" }
    #expect(polls.map { $0.headers["If-Modified-Since"] } == [nil, "Thu, 15 Oct 2026 10:00:00 GMT", nil])
  }

  @Test func threadShiftingAcrossPagesAppearsOnce() async {
    threads.withLock { $0.append($0[0]) }
    let store = makeStore()
    await store.refresh()
    #expect(store.inbox.count == 8)
    #expect(Set(store.inbox.map(\.id)).count == 8)
  }

  @Test func notModifiedKeepsListAndHonoursPollInterval() async {
    let store = makeStore()
    await store.refresh()
    server.on("GET", "/notifications") { request in
      request.headers["If-Modified-Since"] == "Thu, 15 Oct 2026 10:00:00 GMT"
        ? StubResponse(status: 304, headers: ["X-Poll-Interval": "180"]) : StubResponse(status: 500)
    }
    #expect(await store.refresh() == .seconds(180))
    #expect(store.inbox.count == 8)
    #expect(store.issue == nil)
  }

  @Test func pollNowDuringAFetchPollsAgainAtOnce() async throws {
    let calls = Locked(0)
    server.on("GET", "/notifications") { [threads] _ in
      let call = calls.withLock { count in
        count += 1
        return count
      }
      var response = StubResponse.encoded(threads.withLock { $0 }, headers: ["X-OAuth-Scopes": "repo"])
      response.delay = call == 1 ? 2 : 0
      return response
    }
    let store = makeStore()
    store.start()
    try await Task.sleep(for: .milliseconds(50))
    store.pollNow()
    try await Task.sleep(for: .milliseconds(300))
    #expect(store.hasLoaded)
    #expect(calls.withLock { $0 } == 2)
    store.stop()
  }

  @Test func refreshSpinnerStopsBeforeTheBannerWait() async throws {
    let store = InboxStore(
      directory: directory, tokenStorage: MemoryTokenStorage(server.token), session: server.session,
      bannerWait: .seconds(2), networkPaths: AsyncStream { _ in }, now: { Self.now })
    await store.refresh()
    try await Task.sleep(for: .milliseconds(50))
    server.on("GET", "/repos/octo/app/pulls/42", respond: StubResponse(status: 200, body: Data("{}".utf8), delay: 2))
    threads.withLock { list in
      for index in list.indices where list[index].id == "101" { list[index].updatedAt = Self.now }
    }
    let refresh = Task { await store.refresh() }
    try await Task.sleep(for: .milliseconds(200))
    #expect(!store.isRefreshing)
    refresh.cancel()
  }

  @Test func unauthorizedStopsPolling() async {
    server.on("GET", "/notifications", respond: StubResponse(status: 401))
    let store = makeStore()
    #expect(await store.refresh() == nil)
    #expect(store.issue == .unauthorized)
  }

  @Test func missingScopeStopsPolling() async {
    server.on("GET", "/notifications", respond: .json("notifications", headers: ["X-OAuth-Scopes": "notifications"]))
    let store = makeStore()
    #expect(await store.refresh() == nil)
    #expect(store.issue == .missingScope)
  }

  @Test func serverErrorsBackOffThenReportNotResponding() async {
    server.on("GET", "/notifications", respond: StubResponse(status: 502))
    let store = makeStore()
    #expect(await store.refresh() == .seconds(60))
    #expect(store.issue == nil)
    #expect(await store.refresh() == .seconds(120))
    #expect(await store.refresh() == .seconds(300))
    #expect(store.issue == .notResponding)
    #expect(await store.refresh() == .seconds(300))
  }

  @Test func rateLimitPausesUntilReset() async {
    let reset = Self.now.addingTimeInterval(600)
    server.on(
      "GET", "/notifications",
      respond: StubResponse(
        status: 403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(reset.timeIntervalSince1970))"]))
    let store = makeStore()
    #expect(await store.refresh() == .seconds(600))
    #expect(store.issue == .rateLimited(resumesAt: reset))
  }

  @Test func offlineKeepsCachedList() async {
    let store = makeStore()
    await store.refresh()
    server.on("GET", "/notifications", respond: .offline)
    await store.refresh()
    #expect(store.issue == .offline)
    #expect(store.inbox.count == 8)
  }

  @Test func doneMovesRowAndUndoRestoresIt() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["101", "103"])
    #expect(store.done.map(\.id) == ["101", "103"])
    #expect(store.done.allSatisfy { !$0.isUnread })
    #expect(!store.inbox.contains { $0.id == "101" })
    #expect(store.undoableChange?.message == "Marked 2 as done")
    #expect(store.undo() == ["101", "103"])
    #expect(store.done.isEmpty)
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == true)
    #expect(store.pending.isEmpty)
    #expect(requests("PATCH").isEmpty)
  }

  @Test func doneCommitsAfterDelayWithPatchOnly() async throws {
    let store = makeStore(commitDelay: .milliseconds(50))
    await store.refresh()
    store.markDone(["101", "102"])
    try await Task.sleep(for: .milliseconds(300))
    #expect(requests("PATCH") == ["/notifications/threads/101"])
    #expect(requests("DELETE").isEmpty)
    #expect(store.pending.isEmpty)
    #expect(store.done.map(\.id) == ["101", "102"])
    let reloaded = makeStore()
    #expect(reloaded.done.map(\.id) == ["101", "102"])
  }

  @Test func failedCommitRollsBackAndRetries() async {
    server.on("PATCH", "/notifications/threads/101", respond: StubResponse(status: 500))
    let store = makeStore()
    await store.refresh()
    store.markDone(["101", "103"])
    await store.flushPending()
    #expect(store.done.map(\.id) == ["103"])
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == true)
    #expect(store.failure?.count == 1)
    #expect(store.failure?.message == "Couldn't update 1 notification")
    server.on("PATCH", "/notifications/threads/101", respond: StubResponse(status: 205))
    store.retryFailed()
    #expect(store.failure == nil)
    #expect(store.done.map(\.id) == ["101", "103"])
    await store.flushPending()
    #expect(store.pending.isEmpty)
    #expect(store.done.map(\.id) == ["101", "103"])
  }

  @Test func offlineCommitStaysQueued() async {
    server.on("PATCH", "/notifications/threads/101", respond: .offline)
    let store = makeStore()
    await store.refresh()
    store.markRead(["101"])
    await store.flushPending()
    #expect(store.pending.map(\.threadIDs) == [["101"]])
    #expect(store.failure == nil)
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == false)
  }

  @Test func offlineCommitIsResentAfterNextSuccessfulPoll() async throws {
    server.on("PATCH", "/notifications/threads/101", respond: .offline)
    let store = makeStore()
    await store.refresh()
    store.markRead(["101"])
    await store.flushPending()
    #expect(store.pending.count == 1)
    server.on("PATCH", "/notifications/threads/101", respond: StubResponse(status: 205))
    await store.refresh()
    try await Task.sleep(for: .milliseconds(100))
    #expect(store.pending.isEmpty)
    #expect(requests("PATCH") == ["/notifications/threads/101", "/notifications/threads/101"])
  }

  @Test func undoWindowClosesWhileOfflineAndAfterRelaunch() async throws {
    server.on("PATCH", "/notifications/threads/101", respond: .offline)
    let store = makeStore(commitDelay: .milliseconds(50))
    await store.refresh()
    store.markRead(["101"])
    #expect(store.undoableChange?.threadIDs == ["101"])
    try await Task.sleep(for: .milliseconds(300))
    #expect(store.pending.map(\.threadIDs) == [["101"]])
    #expect(store.undoableChange == nil)
    #expect(store.undo().isEmpty)
    #expect(store.pending.count == 1)
    let relaunched = makeStore()
    #expect(relaunched.pending.count == 1)
    relaunched.start()
    #expect(relaunched.undoableChange == nil)
    relaunched.stop()
  }

  @Test func bannerActionsBeforeFirstPollApplyOnceLoaded() async {
    let store = makeStore()
    store.markDone(["101"])
    store.markRead(["103"])
    #expect(store.pending.isEmpty)
    await store.refresh()
    #expect(store.done.map(\.id) == ["101"])
    #expect(store.inbox.first { $0.id == "103" }?.isUnread == false)
    #expect(store.undoableChange == nil)
    await store.flushPending()
    #expect(Set(requests("PATCH")) == ["/notifications/threads/101", "/notifications/threads/103"])
    await store.refresh()
    #expect(store.done.map(\.id) == ["101"])
  }

  @Test func pendingChangesSurviveAPoll() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["101"])
    store.markRead(["103"])
    await store.refresh()
    #expect(store.done.map(\.id) == ["101"])
    #expect(!store.inbox.contains { $0.id == "101" })
    #expect(store.inbox.first { $0.id == "103" }?.isUnread == false)
  }

  @Test func removeAllDoneDeletesEachThread() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["101", "103"])
    store.removeAllDone()
    #expect(store.done.isEmpty)
    await store.flushPending()
    #expect(Set(requests("DELETE")) == ["/notifications/threads/101", "/notifications/threads/103"])
    threads.withLock { $0.removeAll { ["101", "103"].contains($0.id) } }
    await store.refresh()
    #expect(!store.inbox.contains { $0.id == "101" })
  }

  @Test func moveToInboxIsLocal() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["101"])
    await store.flushPending()
    store.moveToInbox(["101"])
    #expect(store.done.isEmpty)
    #expect(store.inbox.first?.id == "101")
    #expect(store.inbox.first?.isUnread == false)
  }

  @Test func moveToInboxBeforeCommitCancelsDoneButStillMarksRead() async throws {
    server.on("PATCH", "/notifications/threads/101") { [threads] _ in
      threads.withLock { list in
        for index in list.indices where list[index].id == "101" { list[index].unread = false }
      }
      return StubResponse(status: 205)
    }
    let store = makeStore()
    await store.refresh()
    store.markDone(["101", "103"])
    store.moveToInbox(["101"])
    #expect(store.undoableChange?.threadIDs == ["103"])
    await store.refresh()
    #expect(store.done.map(\.id) == ["103"])
    #expect(store.inbox.contains { $0.id == "101" })
    await store.flushPending()
    try await Task.sleep(for: .milliseconds(100))
    #expect(Set(requests("PATCH")) == ["/notifications/threads/101", "/notifications/threads/103"])
    #expect(store.pending.isEmpty)
    await store.refresh()
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == false)
  }

  @Test func doneThreadResurfacesWithNewActivity() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["103"])
    await store.flushPending()
    threads.withLock { list in
      let index = list.firstIndex { $0.id == "103" }!
      list[index].updatedAt = Self.now
      list[index].unread = true
    }
    await store.refresh()
    #expect(store.done.isEmpty)
    #expect(store.inbox.first?.id == "103")
    #expect(store.inbox.first?.isUnread == true)
  }

  @Test func threadsDoneOnGitHubDisappear() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["103"])
    await store.flushPending()
    threads.withLock { $0.removeAll { ["103", "102"].contains($0.id) } }
    await store.refresh()
    #expect(store.done.isEmpty)
    #expect(!store.inbox.contains { $0.id == "102" })
  }

  @Test func markAllReadUsesNewestUpdatedAt() async {
    server.on("PUT", "/notifications", respond: StubResponse(status: 202))
    let store = makeStore()
    await store.refresh()
    store.markAllRead()
    #expect(store.unreadCount == 0)
    await store.flushPending()
    let request = server.requests.first { $0.method == "PUT" }
    #expect(request?.json?["last_read_at"] as? String == "2026-10-15T10:00:00Z")
    #expect(store.failure == nil)
  }

  @Test func markAllReadAcceptedLaterStaysReadUntilNewActivity() async {
    server.on("PUT", "/notifications", respond: StubResponse(status: 202))
    let store = makeStore()
    await store.refresh()
    store.markAllRead()
    await store.flushPending()
    await store.refresh()
    #expect(store.unreadCount == 0)
    threads.withLock { list in
      for index in list.indices where list[index].id == "101" { list[index].updatedAt = Self.now }
    }
    await store.refresh()
    #expect(store.unreadCount == 1)
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == true)
  }

  @Test func markAllReadInRepositoryScope() async {
    server.on("PUT", "/repos/octo/lib/notifications", respond: StubResponse(status: 205))
    let store = makeStore()
    await store.refresh()
    store.scope = InboxScope(repository: "octo/lib")
    store.markAllRead()
    await store.flushPending()
    #expect(requests("PUT") == ["/repos/octo/lib/notifications"])
    #expect(store.inbox.filter { $0.thread.repository.fullName == "octo/lib" }.allSatisfy { !$0.isUnread })
    #expect(store.inbox.first { $0.id == "101" }?.isUnread == true)
  }

  @Test func markAllReadWithHiddenThreadsPatchesVisibleOnly() async {
    let store = makeStore()
    await store.refresh()
    store.rules = [FilterRule(conditions: [.repository("octo/lib")])]
    store.markAllRead()
    await store.flushPending()
    #expect(Set(requests("PATCH")) == ["/notifications/threads/101", "/notifications/threads/104", "/notifications/threads/105", "/notifications/threads/108"])
    #expect(requests("PUT").isEmpty)
    #expect(store.inbox.first { $0.id == "103" }?.isUnread == true)
  }

  @Test func markAllReadLeavesHiddenRowsAloneWhileShown() async {
    let store = makeStore()
    await store.refresh()
    store.rules = [FilterRule(conditions: [.repository("octo/lib")])]
    store.showsHidden = true
    store.markAllRead()
    #expect(store.inbox.first { $0.id == "103" }?.isUnread == true)
    await store.flushPending()
    #expect(!requests("PATCH").contains("/notifications/threads/103"))
  }

  @Test func filtersShapeListAndCount() async {
    let store = makeStore()
    await store.refresh()
    #expect(store.unreadCount == 6)
    store.rules = [
      FilterRule(conditions: [.repository("octo/lib")], action: .hide),
      FilterRule(conditions: [.category(.ci)], action: .dontNotify),
    ]
    #expect(store.hiddenCount == 3)
    #expect(store.unreadCount == 4)
    #expect(store.visibleItems.map(\.id) == ["101", "102", "104", "105", "108"])
    store.showsHidden = true
    #expect(store.visibleItems.count == 8)
    store.showsHidden = false
    store.scope = InboxScope(participatingOnly: true)
    #expect(store.visibleItems.map(\.id) == ["101", "102", "108"])
    #expect(store.repositories == ["octo/app", "octo/lib"])
    #expect(makeStore().rules == store.rules)
  }

  @Test func muteThreadUnsubscribesMarksReadAndMovesToDone() async throws {
    server.on("PUT", "/notifications/threads/101/subscription", respond: StubResponse(status: 200))
    let store = makeStore()
    await store.refresh()
    store.muteThread("101")
    #expect(store.done.map(\.id) == ["101"])
    await store.flushPending()
    #expect(server.requests.filter { $0.method != "GET" }.map { "\($0.method) \($0.path)" } == [
      "PUT /notifications/threads/101/subscription", "PATCH /notifications/threads/101",
    ])
    #expect(store.muted.map(\.id) == ["101"])
    try await store.unmute("101")
    #expect(store.muted.isEmpty)
    #expect(server.requests.last { $0.method == "PUT" }?.json?["ignored"] as? Bool == false)
  }

  @Test func muteRepositoryAddsHideRule() async {
    let store = makeStore()
    await store.refresh()
    store.muteRepository("octo/lib")
    store.muteRepository("octo/lib")
    #expect(store.rules.map(\.conditions) == [[.repository("octo/lib")]])
    #expect(store.hiddenCount == 3)
  }

  @Test func optInRulesOnlyActOnThreadsAfterSaving() async throws {
    server.on("DELETE", "/notifications/threads/601", respond: StubResponse(status: 204))
    let store = makeStore()
    store.rules = [
      FilterRule(conditions: [.repository("octo/app")], action: .hideAndMarkDone, savedAt: Fixture.thread("101").updatedAt)
    ]
    await store.refresh()
    addThread("601")
    await store.refresh()
    try await Task.sleep(for: .milliseconds(100))
    #expect(requests("DELETE") == ["/notifications/threads/601"])
    #expect(!store.inbox.contains { $0.id == "601" })
    #expect(store.inbox.contains { $0.id == "101" })
  }

  @Test func enrichesSubjectsAndKeepsThemUntilUpdated() async throws {
    server.on("GET", "/repos/octo/app/pulls/42", respond: .json("pull"))
    server.on("GET", "/repos/octo/app/issues/comments/9001", respond: .json("comment"))
    let store = makeStore()
    await store.refresh()
    try await Task.sleep(for: .milliseconds(200))
    let pull = try #require(store.inbox.first { $0.id == "101" })
    #expect(pull.state == .draft)
    #expect(pull.glyph.tone == .grey)
    #expect(store.inbox.first { $0.id == "105" }?.status == .failed)
    let fetches = server.requests.filter { $0.path == "/repos/octo/app/pulls/42" }.count
    await store.refresh()
    try await Task.sleep(for: .milliseconds(100))
    #expect(server.requests.filter { $0.path == "/repos/octo/app/pulls/42" }.count == fetches)
    #expect(store.inbox.first { $0.id == "101" }?.state == .draft)
  }

  @Test func undecodableFilesAreMovedAsideNotOverwritten() async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let garbage = Data("{ not json".utf8)
    try garbage.write(to: directory.appending(path: "done.json"))
    let store = makeStore()
    await store.refresh()
    store.markDone(["101"])
    #expect(try Data(contentsOf: directory.appending(path: "done.json.corrupt")) == garbage)
    #expect(makeStore().done.map(\.id) == ["101"])
  }

  @Test func disconnectClearsAccountData() async {
    let store = makeStore()
    await store.refresh()
    store.markDone(["101"])
    store.disconnect()
    #expect(!store.isSignedIn)
    #expect(store.inbox.isEmpty)
    #expect(store.done.isEmpty)
    #expect(store.pending.isEmpty)
    #expect(await store.refresh() == .seconds(60))
  }

  @Test func networkLossQueuesChangesAndReconnectFlushesThem() async throws {
    let (paths, network) = AsyncStream.makeStream(of: Bool.self)
    let store = InboxStore(
      directory: directory, tokenStorage: MemoryTokenStorage(server.token), session: server.session,
      commitDelay: .milliseconds(10), networkPaths: paths, now: { Self.now })
    store.start()
    try await Task.sleep(for: .milliseconds(200))
    #expect(store.inbox.count == 8)
    network.yield(false)
    try await Task.sleep(for: .milliseconds(50))
    #expect(store.issue == .offline)
    store.markRead(["101"])
    try await Task.sleep(for: .milliseconds(100))
    #expect(store.pending.count == 1)
    #expect(requests("PATCH").isEmpty)
    network.yield(true)
    try await Task.sleep(for: .milliseconds(200))
    #expect(store.pending.isEmpty)
    #expect(requests("PATCH") == ["/notifications/threads/101"])
    #expect(store.issue == nil)
    store.stop()
  }
}
