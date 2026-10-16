import Foundation
import Network
import Observation

@MainActor
@Observable
public final class InboxStore {
  public static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "dev.gustaf.Tidy")
  public static let summaryThreshold = 5

  public private(set) var inbox: [InboxItem] = []
  public private(set) var done: [InboxItem] = []
  public private(set) var account: GitHubAccount?
  public private(set) var isSignedIn = false
  public private(set) var hasLoaded = false
  public private(set) var isRefreshing = false
  public private(set) var isCapped = false
  public private(set) var issue: SyncIssue?
  public private(set) var lastSync: Date?
  public private(set) var pending: [PendingChange] = []
  public private(set) var failure: ActionFailure?
  public private(set) var muted: [MutedThread] = []
  public private(set) var isOnline = true
  public private(set) var undoableChange: PendingChange?

  public var scope = InboxScope()
  public var showsHidden = false
  public var rules: [FilterRule] = [] {
    didSet { save(rules, as: "rules.json") }
  }
  public var silencedReasons: Set<Reason> = [] {
    didSet { save(silencedReasons, as: "silenced-reasons.json") }
  }

  public let events: AsyncStream<InboxEvent>

  @ObservationIgnored private let continuation: AsyncStream<InboxEvent>.Continuation
  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let tokenStorage: any TokenStorage
  @ObservationIgnored private let session: URLSession
  @ObservationIgnored private let baseURL: URL
  @ObservationIgnored private let cache: ResponseCache
  @ObservationIgnored private let commitDelay: Duration
  @ObservationIgnored private let bannerWait: Duration
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private var networkPaths: AsyncStream<Bool>?
  @ObservationIgnored private var client: GitHubClient?
  @ObservationIgnored private var lastModified: String?
  @ObservationIgnored private var baseline: Date?
  @ObservationIgnored private var pollInterval = Duration.seconds(60)
  @ObservationIgnored private var consecutiveFailures = 0
  @ObservationIgnored private var isRunning = false
  @ObservationIgnored private var isPaused = false
  @ObservationIgnored private var pollTask: Task<Void, Never>?
  @ObservationIgnored private var networkTask: Task<Void, Never>?
  @ObservationIgnored private var commitTasks: [UUID: Task<Void, Never>] = [:]
  @ObservationIgnored private var enriching: Set<String> = []
  @ObservationIgnored private var staleDetails: [String: SubjectDetails] = [:]
  @ObservationIgnored private var ruleActed: Set<String> = []
  @ObservationIgnored private var deferred: [String: PendingAction] = [:]

  public init(
    directory: URL = InboxStore.defaultDirectory,
    tokenStorage: any TokenStorage = KeychainTokenStore(),
    session: URLSession = GitHubClient.makeSession(),
    baseURL: URL = GitHubClient.defaultBaseURL,
    commitDelay: Duration = .seconds(5),
    bannerWait: Duration = .seconds(5),
    networkPaths: AsyncStream<Bool>? = nil,
    now: @escaping @Sendable () -> Date = { .now }
  ) {
    (events, continuation) = AsyncStream.makeStream(of: InboxEvent.self)
    self.directory = directory
    self.tokenStorage = tokenStorage
    self.session = session
    self.baseURL = baseURL
    self.cache = ResponseCache(directory: directory.appending(path: "Cache"))
    self.commitDelay = commitDelay
    self.bannerWait = bannerWait
    self.networkPaths = networkPaths
    self.now = now
    rules = load("rules.json") ?? []
    silencedReasons = load("silenced-reasons.json") ?? []
    done = load("done.json") ?? []
    pending = load("pending.json") ?? []
    muted = load("muted.json") ?? []
    account = load("account.json")
    readToken()
  }

  public var visibleItems: [InboxItem] {
    inbox.filter { scope.contains($0) && (showsHidden || !rules.outcome(for: $0).hides) }
  }

  public var hiddenCount: Int { inbox.count { rules.outcome(for: $0).hides } }
  public var unreadCount: Int { inbox.count { $0.isUnread && !rules.outcome(for: $0).hides } }
  public var repositories: [String] { Set((inbox + done).map(\.thread.repository.fullName)).sorted() }

  public static func networkAvailability() -> AsyncStream<Bool> {
    AsyncStream { continuation in
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
      continuation.onTermination = { _ in monitor.cancel() }
      monitor.start(queue: DispatchQueue(label: "dev.gustaf.Tidy.network"))
    }
  }

  public func connect(token: String) async throws {
    let candidate = GitHubClient(token: token, session: session, baseURL: baseURL, cache: cache)
    let validated = try await candidate.validate()
    try tokenStorage.save(token)
    if account?.user.login != validated.user.login { clearAccountData() }
    resetSync()
    account = validated
    save(validated, as: "account.json")
    client = candidate
    isSignedIn = true
    restartPolling()
  }

  public func disconnect() {
    try? tokenStorage.delete()
    pollTask?.cancel()
    client = nil
    isSignedIn = false
    account = nil
    try? FileManager.default.removeItem(at: directory.appending(path: "account.json"))
    clearAccountData()
    resetSync()
    Task { [cache] in await cache.removeAll() }
  }

  public func start() {
    isRunning = true
    if networkTask == nil {
      let paths = networkPaths ?? Self.networkAvailability()
      networkPaths = nil
      networkTask = Task { [weak self] in
        for await isOnline in paths { self?.networkChanged(isOnline: isOnline) }
      }
    }
    for change in pending where commitTasks[change.id] == nil { schedule(change, after: .zero) }
    restartPolling()
  }

  public func stop() {
    isRunning = false
    pollTask?.cancel()
  }

  public func pause() {
    isPaused = true
    pollTask?.cancel()
  }

  public func resume() {
    isPaused = false
    restartPolling()
  }

  public func pollNow() {
    guard isRunning else {
      Task { await refresh() }
      return
    }
    restartPolling()
  }

  @discardableResult
  public func refresh() async -> Duration? {
    if issue == .keychainUnavailable { readToken() }
    guard let client, !isRefreshing else { return pollInterval }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let fetch = try await client.notifications(since: GitHubClient.since(now: now()), ifModifiedSince: lastModified)
      guard client.token == self.client?.token else { return nil }
      if let scopes = fetch.scopes {
        account?.scopes = scopes
        guard scopes.contains(GitHubClient.requiredScope) else {
          issue = .missingScope
          return nil
        }
      }
      if account == nil, let validated = try? await client.validate(), client.token == self.client?.token {
        account = validated
        save(validated, as: "account.json")
      }
      lastModified = fetch.lastModified
      pollInterval = fetch.pollInterval
      consecutiveFailures = 0
      if case .ssoRequired = issue {} else { issue = nil }
      for change in pending where commitTasks[change.id] == nil { schedule(change, after: .zero) }
      lastSync = now()
      hasLoaded = true
      if let threads = fetch.threads {
        isCapped = !fetch.isComplete
        await merge(threads, isComplete: fetch.isComplete)
      }
      return pollInterval
    } catch is CancellationError {
      return nil
    } catch {
      return handle(error as? GitHubError ?? .decoding)
    }
  }

  public func loadDetails(for id: String) {
    let items = (inbox + done).filter { $0.id == id }
    for item in items { setStatus(.loading, for: item.thread) }
    Task { await enrich(items) }
  }

  public func markRead(_ ids: [String]) {
    let known = Set((inbox + done).map(\.id))
    for id in ids where !known.contains(id) { deferred[id] = .markRead }
    perform(.markRead, items: (inbox + done).filter { ids.contains($0.id) && $0.isUnread })
  }

  public func markDone(_ ids: [String]) {
    let known = Set((inbox + done).map(\.id))
    for id in ids where !known.contains(id) { deferred[id] = .done }
    perform(.done, items: inbox.filter { ids.contains($0.id) })
  }


  public func moveToInbox(_ ids: [String]) {
    let moving = done.filter { ids.contains($0.id) }
    let moved = Set(moving.map(\.id))
    done.removeAll { moved.contains($0.id) }
    inbox = (inbox + moving).sorted { $0.thread.updatedAt > $1.thread.updatedAt }
    let interrupted = pending.filter { [.done, .mute].contains($0.action) && !moved.isDisjoint(with: $0.threadIDs) }
    for change in interrupted {
      let kept = change.restricted(to: Set(change.threadIDs).subtracting(moved))
      if undoableChange?.id == change.id { undoableChange = kept.items.isEmpty ? nil : kept }
      guard kept.items.isEmpty else {
        pending = pending.map { $0.id == change.id ? kept : $0 }
        continue
      }
      pending.removeAll { $0.id == change.id }
      commitTasks.removeValue(forKey: change.id)?.cancel()
    }
    save(pending, as: "pending.json")
    save(done, as: "done.json")
    perform(.markRead, items: interrupted.flatMap { $0.items.filter { moved.contains($0.id) } }, delay: .zero)
  }

  public func removeAllDone() {
    perform(.remove, items: done)
  }

  public func markAllRead() {
    let unread = inbox.filter(\.isUnread)
    let newest = (inbox + done).map(\.thread.updatedAt).max() ?? now()
    if scope.participatingOnly || hiddenCount > 0 {
      perform(.markAllRead(.visibleThreads), items: unread.filter { scope.contains($0) && !rules.outcome(for: $0).hides })
    } else if let repository = scope.repository {
      perform(.markAllRead(.repository(repository, lastReadAt: newest)), items: unread.filter { scope.contains($0) })
    } else {
      perform(.markAllRead(.everything(lastReadAt: newest)), items: unread)
    }
  }

  public func muteThread(_ id: String) {
    perform(.mute, items: inbox.filter { $0.id == id })
  }

  public func muteRepository(_ fullName: String) {
    guard !rules.contains(where: { $0.conditions == [.repository(fullName)] && $0.action.hides }) else { return }
    rules.append(FilterRule(conditions: [.repository(fullName)], action: .hide, savedAt: now()))
  }

  public func unmute(_ id: String) async throws {
    guard let client else { throw GitHubError.unauthorized }
    try await client.unmute(threadID: id)
    muted.removeAll { $0.id == id }
    save(muted, as: "muted.json")
  }

  @discardableResult
  public func undo() -> [String] {
    guard let id = undoableChange?.id else { return [] }
    undoableChange = nil
    guard let index = pending.firstIndex(where: { $0.id == id }) else { return [] }
    let change = pending.remove(at: index)
    commitTasks.removeValue(forKey: id)?.cancel()
    revert(change)
    save(pending, as: "pending.json")
    save(done, as: "done.json")
    return change.threadIDs
  }

  public func flushPending() async {
    for change in pending {
      commitTasks.removeValue(forKey: change.id)?.cancel()
      await commit(change.id)
    }
  }

  public func retryFailed() {
    guard let failure else { return }
    self.failure = nil
    for change in failure.changes {
      let ids = Set(change.threadIDs)
      perform(change.action, items: (inbox + done).filter { ids.contains($0.id) }, delay: .zero)
    }
  }

  public func dismissFailure() {
    failure = nil
  }

  private func restartPolling() {
    let previous = pollTask
    previous?.cancel()
    guard isSignedIn, isRunning, !isPaused, isOnline else { return }
    pollTask = Task { [weak self] in
      await previous?.value
      while !Task.isCancelled, let delay = await self?.refresh() {
        try? await Task.sleep(for: delay)
      }
    }
  }

  private func readToken() {
    do {
      let token = try tokenStorage.read()
      client = token.map { GitHubClient(token: $0, session: session, baseURL: baseURL, cache: cache) }
      isSignedIn = token != nil
      if issue == .keychainUnavailable { issue = nil }
    } catch {
      isSignedIn = true
      issue = .keychainUnavailable
    }
  }

  private func networkChanged(isOnline: Bool) {
    guard isOnline != self.isOnline else { return }
    self.isOnline = isOnline
    guard isOnline else {
      pollTask?.cancel()
      issue = .offline
      return
    }
    if issue == .offline { issue = nil }
    for change in pending where commitTasks[change.id] == nil { schedule(change, after: .zero) }
    restartPolling()
  }

  private func handle(_ error: GitHubError) -> Duration? {
    switch error {
    case .unauthorized, .fineGrainedToken:
      issue = .unauthorized
      return nil
    case .missingScopes:
      issue = .missingScope
      return nil
    case .rateLimited(let resetsAt):
      issue = .rateLimited(resumesAt: resetsAt)
      return .seconds(max(60, resetsAt.timeIntervalSince(now())))
    case .offline:
      issue = .offline
      return .seconds(60)
    case .ssoRequired(let organization, let url):
      issue = .ssoRequired(organization: organization, url: url)
      return pollInterval
    default:
      consecutiveFailures += 1
      if consecutiveFailures >= 3 { issue = .notResponding }
      return .seconds([60, 120, 300][min(consecutiveFailures, 3) - 1])
    }
  }

  private func merge(_ threads: [NotificationThread], isComplete: Bool) async {
    let since = GitHubClient.since(now: now())
    let cutoff = isComplete ? since : threads.map(\.updatedAt).min() ?? since
    var seen: Set<String> = []
    let unique = threads.filter { seen.insert($0.id).inserted }
    let fresh = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
    let previous = Dictionary((done + inbox).map { ($0.id, $0) }) { first, _ in first }
    let readElsewhere = unique.filter { !$0.unread && previous[$0.id]?.isUnread == true }.map(\.id)
    if !readElsewhere.isEmpty { continuation.yield(.withdraw(threadIDs: readElsewhere)) }
    done = done.filter { item in
      guard let thread = fresh[item.id] else { return item.thread.updatedAt < cutoff }
      return !(thread.unread && thread.updatedAt > item.thread.updatedAt)
    }
    let doneIDs = Set(done.map(\.id))
    inbox = unique.filter { !doneIDs.contains($0.id) }.sorted { $0.updatedAt > $1.updatedAt }.map { thread in
      guard let old = previous[thread.id], old.thread.updatedAt == thread.updatedAt else {
        staleDetails[thread.id] = previous[thread.id]?.details
        return InboxItem(thread: thread)
      }
      return InboxItem(thread: thread, status: old.status)
    }
    for change in pending { apply(change) }
    save(done, as: "done.json")
    let waiting = deferred
    deferred = [:]
    perform(.markRead, items: (inbox + done).filter { waiting[$0.id] == .markRead && $0.isUnread }, delay: .zero)
    perform(.done, items: inbox.filter { waiting[$0.id] == .done }, delay: .zero)

    let enrichment = Task { await enrich((inbox + done).filter { $0.status == .loading && !enriching.contains($0.id) }) }
    let newest = threads.map(\.updatedAt).max()
    guard let baseline else {
      self.baseline = newest ?? since
      runRuleActions()
      return
    }
    self.baseline = max(baseline, newest ?? baseline)
    let candidates = inbox.filter {
      $0.thread.updatedAt > baseline && $0.isUnread && !silencedReasons.contains($0.thread.reason)
    }.map(\.id)
    guard !candidates.isEmpty else {
      runRuleActions()
      return
    }
    isRefreshing = false
    await announce(candidates, after: enrichment)
  }

  private func announce(_ candidates: [String], after enrichment: Task<Void, Never>) async {
    await withTaskGroup(of: Void.self) { [bannerWait] group in
      group.addTask { await enrichment.value }
      group.addTask { try? await Task.sleep(for: bannerWait) }
      await group.next()
      group.cancelAll()
    }
    runRuleActions()
    let notifiable = inbox.filter { candidates.contains($0.id) && !rules.outcome(for: $0).silences }
    guard notifiable.count <= Self.summaryThreshold else {
      continuation.yield(.summary(count: notifiable.count))
      return
    }
    for item in notifiable { continuation.yield(.newThread(item)) }
  }

  private func enrich(_ items: [InboxItem]) async {
    guard let client, !items.isEmpty else { return }
    enriching.formUnion(items.map(\.id))
    let jobs = items.map { ($0.thread, staleDetails[$0.id] ?? $0.details) }
    await withTaskGroup(of: (NotificationThread, Result<SubjectDetails, any Error>).self) { group in
      for (offset, (thread, previous)) in jobs.enumerated() {
        if offset >= 4, let (finished, result) = await group.next() { finishEnrichment(of: finished, with: result) }
        group.addTask {
          do {
            return (thread, .success(try await client.details(for: thread, previous: previous)))
          } catch {
            return (thread, .failure(error))
          }
        }
      }
      for await (thread, result) in group { finishEnrichment(of: thread, with: result) }
    }
  }

  private func finishEnrichment(of thread: NotificationThread, with result: Result<SubjectDetails, any Error>) {
    enriching.remove(thread.id)
    staleDetails[thread.id] = nil
    switch result {
    case .success(let details):
      if case .ssoRequired(let organization, _) = issue,
        organization?.caseInsensitiveCompare(thread.repository.owner.login) == .orderedSame
      {
        issue = nil
      }
      setStatus(.loaded(details), for: thread)
    case .failure(let error):
      if case .ssoRequired(let organization, let url) = error as? GitHubError {
        issue = .ssoRequired(organization: organization, url: url)
      }
      setStatus(.failed, for: thread)
    }
  }

  private func setStatus(_ status: DetailsStatus, for thread: NotificationThread) {
    if let index = inbox.firstIndex(where: { $0.id == thread.id && $0.thread.updatedAt == thread.updatedAt }) {
      inbox[index].status = status
    }
    if let index = done.firstIndex(where: { $0.id == thread.id && $0.thread.updatedAt == thread.updatedAt }) {
      done[index].status = status
      save(done, as: "done.json")
    }
  }

  private func runRuleActions() {
    guard let client else { return }
    var reads: [String] = []
    var removals: [String] = []
    for item in inbox {
      guard case .matched(let rule) = rules.outcome(for: item), rule.action.isOptIn,
        item.thread.updatedAt > rule.savedAt
      else { continue }
      let key = "\(item.id)@\(item.thread.updatedAt.timeIntervalSince1970)"
      guard ruleActed.insert(key).inserted else { continue }
      if rule.action == .hideAndMarkDone {
        removals.append(item.id)
      } else if item.isUnread {
        reads.append(item.id)
      }
    }
    guard !reads.isEmpty || !removals.isEmpty else { return }
    inbox.removeAll { removals.contains($0.id) }
    for index in inbox.indices where reads.contains(inbox[index].id) { inbox[index].thread.unread = false }
    Task {
      _ = await Self.forEach(reads) { try await client.markRead(threadID: $0) }
      _ = await Self.forEach(removals) { try await client.remove(threadID: $0) }
    }
  }

  private func perform(_ action: PendingAction, items: [InboxItem], delay: Duration? = nil) {
    guard !items.isEmpty else { return }
    let change = PendingChange(action: action, items: items)
    pending.append(change)
    apply(change)
    save(pending, as: "pending.json")
    save(done, as: "done.json")
    continuation.yield(.withdraw(threadIDs: change.threadIDs))
    schedule(change, after: delay ?? commitDelay)
    guard delay == nil else { return }
    undoableChange = change
    Task { [weak self, commitDelay] in
      try? await Task.sleep(for: commitDelay)
      guard self?.undoableChange?.id == change.id else { return }
      self?.undoableChange = nil
    }
  }

  private func schedule(_ change: PendingChange, after delay: Duration) {
    commitTasks[change.id] = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await self?.commit(change.id)
    }
  }

  private func commit(_ id: UUID) async {
    commitTasks[id] = nil
    guard let client, isOnline, let index = pending.firstIndex(where: { $0.id == id }) else { return }
    if undoableChange?.id == id { undoableChange = nil }
    let change = pending.remove(at: index)
    save(pending, as: "pending.json")
    let errors = await Self.send(change, client: client)
    let succeeded = change.items.filter { errors[$0.id] == nil }
    if change.action == .mute, !succeeded.isEmpty {
      muted += succeeded.map {
        MutedThread(id: $0.id, title: $0.title, repository: $0.thread.repository.fullName)
      }
      save(muted, as: "muted.json")
    }
    guard !errors.isEmpty else { return }
    let offline = Set(errors.filter { $0.value as? GitHubError == .offline }.keys)
    if !offline.isEmpty {
      pending.insert(change.restricted(to: offline), at: 0)
      save(pending, as: "pending.json")
    }
    let failed = Set(errors.keys).subtracting(offline)
    guard !failed.isEmpty else { return }
    let failedChange = change.restricted(to: failed)
    revert(failedChange)
    save(done, as: "done.json")
    failure = ActionFailure(changes: (failure?.changes ?? []) + [failedChange])
  }

  private func apply(_ change: PendingChange) {
    let ids = Set(change.threadIDs)
    switch change.action {
    case .markRead, .markAllRead:
      for index in inbox.indices where ids.contains(inbox[index].id) { inbox[index].thread.unread = false }
      for index in done.indices where ids.contains(done[index].id) { done[index].thread.unread = false }
    case .done, .mute:
      let moving = inbox.filter { ids.contains($0.id) }.map { item in
        var item = item
        item.thread.unread = false
        return item
      }
      let movingIDs = Set(moving.map(\.id))
      inbox.removeAll { movingIDs.contains($0.id) }
      done.removeAll { movingIDs.contains($0.id) }
      done.insert(contentsOf: moving, at: 0)
    case .remove:
      inbox.removeAll { ids.contains($0.id) }
      done.removeAll { ids.contains($0.id) }
    }
  }

  private func revert(_ change: PendingChange) {
    let snapshot = Dictionary(change.items.map { ($0.id, $0) }) { first, _ in first }
    switch change.action {
    case .markRead, .markAllRead:
      for index in inbox.indices {
        if let original = snapshot[inbox[index].id] { inbox[index].thread.unread = original.isUnread }
      }
      for index in done.indices {
        if let original = snapshot[done[index].id] { done[index].thread.unread = original.isUnread }
      }
    case .done, .mute:
      done.removeAll { snapshot[$0.id] != nil }
      let present = Set(inbox.map(\.id))
      inbox = (inbox + change.items.filter { !present.contains($0.id) }).sorted { $0.thread.updatedAt > $1.thread.updatedAt }
    case .remove:
      let present = Set(done.map(\.id))
      done += change.items.filter { !present.contains($0.id) }
    }
  }

  nonisolated private static func send(_ change: PendingChange, client: GitHubClient) async -> [String: any Error] {
    let unread = change.items.filter(\.isUnread).map(\.id)
    switch change.action {
    case .markRead, .done, .markAllRead(.visibleThreads):
      return await forEach(unread) { try await client.markRead(threadID: $0) }
    case .remove:
      return await forEach(change.threadIDs) { try await client.remove(threadID: $0) }
    case .mute:
      return await forEach(change.threadIDs) { id in
        try await client.mute(threadID: id)
        if unread.contains(id) { try await client.markRead(threadID: id) }
      }
    case .markAllRead(.everything(let lastReadAt)), .markAllRead(.repository(_, let lastReadAt)):
      let repository: String? = if case .markAllRead(.repository(let name, _)) = change.action { name } else { nil }
      do {
        try await client.markAllRead(lastReadAt: lastReadAt, repository: repository)
        return [:]
      } catch {
        return Dictionary(change.threadIDs.map { ($0, error) }) { first, _ in first }
      }
    }
  }

  nonisolated private static func forEach(
    _ ids: [String], limit: Int = 4, operation: @escaping @Sendable (String) async throws -> Void
  ) async -> [String: any Error] {
    await withTaskGroup(of: (String, (any Error)?).self) { group in
      var errors: [String: any Error] = [:]
      for (offset, id) in ids.enumerated() {
        if offset >= limit, let (finished, error) = await group.next(), let error { errors[finished] = error }
        group.addTask {
          do {
            try await operation(id)
            return (id, nil)
          } catch {
            return (id, error)
          }
        }
      }
      for await (id, error) in group {
        if let error { errors[id] = error }
      }
      return errors
    }
  }

  private func resetSync() {
    pollTask?.cancel()
    inbox = []
    baseline = nil
    lastModified = nil
    hasLoaded = false
    issue = nil
    lastSync = nil
    consecutiveFailures = 0
    isCapped = false
  }

  private func clearAccountData() {
    for task in commitTasks.values { task.cancel() }
    commitTasks = [:]
    pending = []
    undoableChange = nil
    deferred = [:]
    done = []
    muted = []
    failure = nil
    save(pending, as: "pending.json")
    save(done, as: "done.json")
    save(muted, as: "muted.json")
  }

  private func load<T: Decodable>(_ name: String) -> T? {
    guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  private func save(_ value: some Encodable, as name: String) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? JSONEncoder().encode(value).write(to: directory.appending(path: name), options: .atomic)
  }
}
