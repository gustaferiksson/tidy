import Foundation

public struct ThreadDetails: Hashable, Sendable {
  public var author: GitHubUser?
  public var createdAt: Date?
  public var url: URL?
  public var body: String
  public var labels: [IssueLabel]
  public var assignees: [GitHubUser]
  public var milestone: String?
  public var timeline: [TimelineEntry]
  public var totalTimelineItems: Int
  public var hasOlderTimelineItems: Bool
  public var pullRequest: PullRequestDetails?
  public var discussion: DiscussionDetails?

  public init(
    author: GitHubUser? = nil,
    createdAt: Date? = nil,
    url: URL? = nil,
    body: String = "",
    labels: [IssueLabel] = [],
    assignees: [GitHubUser] = [],
    milestone: String? = nil,
    timeline: [TimelineEntry] = [],
    totalTimelineItems: Int = 0,
    hasOlderTimelineItems: Bool = false,
    pullRequest: PullRequestDetails? = nil,
    discussion: DiscussionDetails? = nil
  ) {
    self.author = author
    self.createdAt = createdAt
    self.url = url
    self.body = body
    self.labels = labels
    self.assignees = assignees
    self.milestone = milestone
    self.timeline = timeline
    self.totalTimelineItems = totalTimelineItems
    self.hasOlderTimelineItems = hasOlderTimelineItems
    self.pullRequest = pullRequest
    self.discussion = discussion
  }

  public static func isSupported(_ thread: NotificationThread) -> Bool {
    thread.subject.kind == .discussion || thread.number != nil
  }
}

public struct IssueLabel: Hashable, Sendable, Identifiable {
  public var name: String
  public var color: String

  public init(name: String, color: String) {
    self.name = name
    self.color = color
  }

  public var id: String { name }
}

public struct PullRequestDetails: Hashable, Sendable {
  public var baseBranch: String
  public var headBranch: String
  public var additions: Int
  public var deletions: Int
  public var changedFiles: Int
  public var reviewDecision: ReviewDecision?
  public var reviewers: [Reviewer]
  public var checks: CheckSummary?
  public var hasConflicts: Bool

  public init(
    baseBranch: String,
    headBranch: String,
    additions: Int = 0,
    deletions: Int = 0,
    changedFiles: Int = 0,
    reviewDecision: ReviewDecision? = nil,
    reviewers: [Reviewer] = [],
    checks: CheckSummary? = nil,
    hasConflicts: Bool = false
  ) {
    self.baseBranch = baseBranch
    self.headBranch = headBranch
    self.additions = additions
    self.deletions = deletions
    self.changedFiles = changedFiles
    self.reviewDecision = reviewDecision
    self.reviewers = reviewers
    self.checks = checks
    self.hasConflicts = hasConflicts
  }
}

public enum ReviewDecision: String, Hashable, Sendable {
  case approved, changesRequested, reviewRequired

  public var title: String {
    switch self {
    case .approved: "Approved"
    case .changesRequested: "Changes requested"
    case .reviewRequired: "Review required"
    }
  }
}

public enum ReviewState: String, Codable, Hashable, Sendable {
  case approved, changesRequested, commented, dismissed, requested

  init?(apiValue: String?) {
    let states: [String: ReviewState] = [
      "APPROVED": .approved, "CHANGES_REQUESTED": .changesRequested, "COMMENTED": .commented, "DISMISSED": .dismissed,
    ]
    guard let state = apiValue.flatMap({ states[$0] }) else { return nil }
    self = state
  }

  public var title: String {
    switch self {
    case .approved: "Approved"
    case .changesRequested: "Changes requested"
    case .commented: "Commented"
    case .dismissed: "Dismissed"
    case .requested: "Review requested"
    }
  }
}

public struct Reviewer: Hashable, Sendable, Identifiable {
  public var user: GitHubUser
  public var state: ReviewState

  public init(user: GitHubUser, state: ReviewState) {
    self.user = user
    self.state = state
  }

  public var id: String { user.login }
}

public enum CheckState: String, Hashable, Sendable {
  case success, failure, pending
}

public struct CheckSummary: Hashable, Sendable {
  public var state: CheckState
  public var passed: Int
  public var failing: [String]
  public var pending: [String]

  public init(state: CheckState, passed: Int, failing: [String] = [], pending: [String] = []) {
    self.state = state
    self.passed = passed
    self.failing = failing
    self.pending = pending
  }

  public var summary: String {
    let passedPart = passed == 0 ? nil : passed == 1 ? "1 check passed" : "\(passed) checks passed"
    let failingNames = failing.prefix(3).joined(separator: ", ") + (failing.count > 3 ? " +\(failing.count - 3)" : "")
    let failingPart = failing.isEmpty ? nil : "\(failing.count) failing: \(failingNames)"
    let pendingPart = pending.isEmpty ? nil : "\(pending.count) pending"
    let parts = [passedPart, failingPart, pendingPart].compactMap(\.self)
    return parts.isEmpty ? "No checks reported" : parts.joined(separator: " · ")
  }
}

public struct DiscussionDetails: Hashable, Sendable {
  public var category: String?
  public var isAnswered: Bool

  public init(category: String?, isAnswered: Bool) {
    self.category = category
    self.isAnswered = isAnswered
  }
}

public struct TimelineComment: Hashable, Sendable, Identifiable {
  public var id: String
  public var author: GitHubUser?
  public var body: String
  public var createdAt: Date
  public var url: URL?
  public var review: ReviewState?
  public var isAnswer: Bool

  public init(id: String, author: GitHubUser?, body: String, createdAt: Date, url: URL?, review: ReviewState? = nil, isAnswer: Bool = false) {
    self.id = id
    self.author = author
    self.body = body
    self.createdAt = createdAt
    self.url = url
    self.review = review
    self.isAnswer = isAnswer
  }
}

public enum TimelineEntry: Hashable, Sendable, Identifiable {
  case comment(TimelineComment)
  case event(TimelineEvent)

  public var id: String {
    switch self {
    case .comment(let comment): comment.id
    case .event(let event): event.id
    }
  }
}

public struct TimelineEvent: Hashable, Sendable, Identifiable {
  public enum Kind: Hashable, Sendable {
    case committed([CommitSummary])
    case forcePushed(branch: String?)
    case deletedBranch(String?)
    case requestedReview(from: [GitHubUser])
    case removedReviewRequest(from: GitHubUser?)
    case merged(into: String?)
    case closed, reopened, readyForReview, convertedToDraft
    case labeled(IssueLabel)
    case unlabeled(IssueLabel)
    case assigned(GitHubUser)
    case unassigned(GitHubUser)
    case renamed(from: String, to: String)
    case crossReferenced(CrossReference)
  }

  public var id: String
  public var actor: GitHubUser?
  public var kind: Kind
  public var date: Date

  public init(id: String, actor: GitHubUser?, kind: Kind, date: Date) {
    self.id = id
    self.actor = actor
    self.kind = kind
    self.date = date
  }

  func absorbing(_ next: TimelineEvent) -> TimelineEvent? {
    guard next.actor?.login == actor?.login else { return nil }
    if case .committed(let commits) = kind, case .committed(let more) = next.kind {
      return TimelineEvent(id: id, actor: actor, kind: .committed(commits + more), date: next.date)
    }
    guard case .requestedReview(let reviewers) = kind, case .requestedReview(let more) = next.kind, next.date.timeIntervalSince(date) < 60
    else { return nil }
    return TimelineEvent(id: id, actor: actor, kind: .requestedReview(from: reviewers + more), date: next.date)
  }
}

public struct CommitSummary: Hashable, Sendable {
  public var shortSHA: String
  public var headline: String
  public var url: URL?

  public init(shortSHA: String, headline: String, url: URL? = nil) {
    self.shortSHA = shortSHA
    self.headline = headline
    self.url = url
  }
}

public struct CrossReference: Hashable, Sendable {
  public var repository: String
  public var number: Int
  public var title: String
  public var url: URL?

  public init(repository: String, number: Int, title: String, url: URL? = nil) {
    self.repository = repository
    self.number = number
    self.title = title
    self.url = url
  }
}

public enum ThreadDetailsStatus: Hashable, Sendable {
  case loading
  case loaded(ThreadDetails)
  case unavailable
  case failed

  public var details: ThreadDetails? {
    guard case .loaded(let details) = self else { return nil }
    return details
  }
}

extension GitHubClient {
  public func threadDetails(for thread: NotificationThread, scopes: [String]) async throws -> ThreadDetails {
    let fullName = thread.repository.fullName
    if thread.subject.kind == .discussion {
      let title = thread.subject.title.replacing("\"", with: "")
      let search = "repo:\(fullName) in:title \"\(title)\""
      return try await graphQL(SearchData.self, query: Self.discussionQuery, variables: ["query": search]) { data in
        data.search?.items.first { $0.title == thread.subject.title }?.details
      }
    }
    let parts = fullName.split(separator: "/", maxSplits: 1).map(String.init)
    guard let number = thread.number, parts.count == 2 else { throw GitHubError.notFound }
    let variables: [String: Any] = ["owner": parts[0], "name": parts[1], "number": number]
    let readsTeams = scopes.contains { ["read:org", "write:org", "admin:org"].contains($0) }
    // GitHub rejects the whole query, not just the field, when any Team field is selected without read:org.
    let query = Self.issueOrPullRequestQuery(teamReviewer: readsTeams ? "... on Team { slug avatarUrl(size: 40) }" : "")
    return try await graphQL(RepositoryData.self, query: query, variables: variables) {
      $0.repository?.issueOrPullRequest?.details
    }
  }

  static let conversationLimit = 50

  static func issueOrPullRequestQuery(teamReviewer: String) -> String {
    let shared = """
      type: __typename
      ... on IssueComment { id author { ...Who } body createdAt url }
      ... on ClosedEvent { id actor { ...Who } createdAt }
      ... on ReopenedEvent { id actor { ...Who } createdAt }
      ... on LabeledEvent { id actor { ...Who } createdAt label { name color } }
      ... on UnlabeledEvent { id actor { ...Who } createdAt label { name color } }
      ... on AssignedEvent { id actor { ...Who } createdAt assignee { ...Who } }
      ... on UnassignedEvent { id actor { ...Who } createdAt assignee { ...Who } }
      ... on RenamedTitleEvent { id actor { ...Who } createdAt previousTitle currentTitle }
      ... on CrossReferencedEvent { id actor { ...Who } createdAt source { ...Reference } }
      """
    return """
      query($owner: String!, $name: String!, $number: Int!) {
        repository(owner: $owner, name: $name) {
          issueOrPullRequest(number: $number) {
            kind: __typename
            ... on Issue {
              author { ...Who } createdAt url body
              labels(first: 20) { nodes { name color } }
              assignees(first: 10) { nodes { ...Who } }
              milestone { title }
              timelineItems(last: \(conversationLimit), itemTypes: [ISSUE_COMMENT, CLOSED_EVENT, REOPENED_EVENT, LABELED_EVENT, UNLABELED_EVENT, ASSIGNED_EVENT, UNASSIGNED_EVENT, RENAMED_TITLE_EVENT, CROSS_REFERENCED_EVENT]) { filteredCount nodes {
                \(shared)
              } }
            }
            ... on PullRequest {
              author { ...Who } createdAt url body
              labels(first: 20) { nodes { name color } }
              assignees(first: 10) { nodes { ...Who } }
              milestone { title }
              baseRefName headRefName additions deletions changedFiles mergeable reviewDecision
              latestReviews(first: 20) { nodes { state author { ...Who } } }
              reviewRequests(first: 20) { nodes { requestedReviewer { ...Who \(teamReviewer) } } }
              commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 100) { nodes {
                ... on CheckRun { name status conclusion }
                ... on StatusContext { context state }
              } } } } } }
              timelineItems(last: \(conversationLimit), itemTypes: [PULL_REQUEST_COMMIT, ISSUE_COMMENT, PULL_REQUEST_REVIEW, REVIEW_REQUESTED_EVENT, REVIEW_REQUEST_REMOVED_EVENT, MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT, HEAD_REF_FORCE_PUSHED_EVENT, HEAD_REF_DELETED_EVENT, READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT, LABELED_EVENT, UNLABELED_EVENT, ASSIGNED_EVENT, UNASSIGNED_EVENT, RENAMED_TITLE_EVENT, CROSS_REFERENCED_EVENT]) { filteredCount nodes {
                \(shared)
                ... on PullRequestCommit { id commit { abbreviatedOid messageHeadline committedDate url author { name user { ...Who } } } }
                ... on PullRequestReview { id author { ...Who } body createdAt url state }
                ... on ReviewRequestedEvent { id actor { ...Who } createdAt requestedReviewer { ...Who \(teamReviewer) } }
                ... on ReviewRequestRemovedEvent { id actor { ...Who } createdAt requestedReviewer { ...Who \(teamReviewer) } }
                ... on MergedEvent { id actor { ...Who } createdAt mergeRefName }
                ... on HeadRefForcePushedEvent { id actor { ...Who } createdAt ref { name } }
                ... on HeadRefDeletedEvent { id actor { ...Who } createdAt headRefName }
                ... on ReadyForReviewEvent { id actor { ...Who } createdAt }
                ... on ConvertToDraftEvent { id actor { ...Who } createdAt }
              } }
            }
          }
        }
      }
      fragment Who on Actor { login avatarUrl(size: 40) }
      fragment Reference on ReferencedSubject {
        ... on Issue { number title url repository { nameWithOwner } }
        ... on PullRequest { number title url repository { nameWithOwner } }
      }
      """
  }

  static let discussionQuery = """
    query($query: String!) {
      search(query: $query, type: DISCUSSION, first: 5) {
        nodes {
          ... on Discussion {
            kind: __typename
            title author { ...Who } createdAt url body isAnswered
            category { name }
            labels(first: 20) { nodes { name color } }
            comments(last: 10) { totalCount nodes { id author { ...Who } body createdAt url isAnswer } }
          }
        }
      }
    }
    fragment Who on Actor { login avatarUrl(size: 40) }
    """
}

private struct RepositoryData: Decodable {
  struct Repository: Decodable {
    let issueOrPullRequest: SubjectNode?
  }

  let repository: Repository?
}

private struct SearchData: Decodable {
  let search: Connection<SubjectNode>?
}

struct Connection<Node: Decodable>: Decodable {
  private struct Lossy: Decodable {
    let node: Node?

    init(from decoder: any Decoder) throws {
      node = try? Node(from: decoder)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case totalCount, filteredCount, nodes
  }

  let totalCount: Int?
  let fetchedCount: Int
  let items: [Node]

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    totalCount = try container.decodeIfPresent(Int.self, forKey: .filteredCount) ?? container.decodeIfPresent(Int.self, forKey: .totalCount)
    let nodes = (try? container.decodeIfPresent([Lossy].self, forKey: .nodes)) ?? []
    fetchedCount = nodes.count
    items = nodes.compactMap(\.node)
  }
}

struct ActorNode: Decodable {
  let login: String?
  let slug: String?
  let avatarUrl: URL?

  var user: GitHubUser? { (login ?? slug).map { GitHubUser(login: $0, avatarURL: avatarUrl) } }
}

struct LabelNode: Decodable {
  let name: String
  let color: String?

  var label: IssueLabel { IssueLabel(name: name, color: color ?? "ededed") }
}

struct TimelineNode: Decodable {
  struct Commit: Decodable {
    struct Author: Decodable {
      let name: String?
      let user: ActorNode?
    }

    let abbreviatedOid: String?
    let messageHeadline: String?
    let committedDate: Date?
    let url: URL?
    let author: Author?
  }

  struct Ref: Decodable {
    let name: String?
  }

  struct Source: Decodable {
    struct Repository: Decodable {
      let nameWithOwner: String
    }

    let number: Int?
    let title: String?
    let url: URL?
    let repository: Repository?
  }

  let type: String?
  let id: String?
  let author: ActorNode?
  let actor: ActorNode?
  let body: String?
  let createdAt: Date?
  let url: URL?
  let state: String?
  let isAnswer: Bool?
  let requestedReviewer: ActorNode?
  let assignee: ActorNode?
  let commit: Commit?
  let label: LabelNode?
  let mergeRefName: String?
  let headRefName: String?
  let ref: Ref?
  let previousTitle: String?
  let currentTitle: String?
  let source: Source?

  var entry: TimelineEntry? {
    guard let id else { return nil }
    if type == nil || type == "IssueComment" || type == "PullRequestReview" {
      guard let createdAt, state != "COMMENTED" || !(body ?? "").isEmpty else { return nil }
      return .comment(TimelineComment(
        id: id, author: author?.user, body: body ?? "", createdAt: createdAt, url: url,
        review: ReviewState(apiValue: state), isAnswer: isAnswer ?? false))
    }
    let committer = commit?.author.flatMap { $0.user?.user ?? $0.name.map { GitHubUser(login: $0) } }
    guard let kind = eventKind, let date = createdAt ?? commit?.committedDate else { return nil }
    return .event(TimelineEvent(id: id, actor: actor?.user ?? committer, kind: kind, date: date))
  }

  private var eventKind: TimelineEvent.Kind? {
    switch type {
    case "PullRequestCommit":
      guard let sha = commit?.abbreviatedOid else { return nil }
      return .committed([CommitSummary(shortSHA: String(sha.prefix(7)), headline: commit?.messageHeadline ?? "", url: commit?.url)])
    case "HeadRefForcePushedEvent": return .forcePushed(branch: ref?.name)
    case "HeadRefDeletedEvent": return .deletedBranch(headRefName)
    case "ReviewRequestedEvent": return .requestedReview(from: requestedReviewer?.user.map { [$0] } ?? [])
    case "ReviewRequestRemovedEvent": return .removedReviewRequest(from: requestedReviewer?.user)
    case "MergedEvent": return .merged(into: mergeRefName)
    case "ClosedEvent": return .closed
    case "ReopenedEvent": return .reopened
    case "ReadyForReviewEvent": return .readyForReview
    case "ConvertToDraftEvent": return .convertedToDraft
    case "LabeledEvent": return label.map { .labeled($0.label) }
    case "UnlabeledEvent": return label.map { .unlabeled($0.label) }
    case "AssignedEvent": return assignee?.user.map { .assigned($0) }
    case "UnassignedEvent": return assignee?.user.map { .unassigned($0) }
    case "RenamedTitleEvent":
      guard let previousTitle, let currentTitle else { return nil }
      return .renamed(from: previousTitle, to: currentTitle)
    case "CrossReferencedEvent":
      guard let repository = source?.repository?.nameWithOwner, let number = source?.number else { return nil }
      return .crossReferenced(CrossReference(repository: repository, number: number, title: source?.title ?? "", url: source?.url))
    default: return nil
    }
  }

  static func timeline(of nodes: [TimelineNode]) -> [TimelineEntry] {
    var entries: [TimelineEntry] = []
    for entry in nodes.compactMap(\.entry) {
      guard case .event(let event) = entry, case .event(let previous)? = entries.last else {
        entries.append(entry)
        continue
      }
      if case .merged = previous.kind, event.kind == .closed { continue }
      if let combined = previous.absorbing(event) {
        entries[entries.count - 1] = .event(combined)
      } else {
        entries.append(entry)
      }
    }
    return entries
  }
}

private struct SubjectNode: Decodable {
  struct Title: Decodable {
    let title: String?
    let name: String?
  }

  struct Review: Decodable {
    let state: String?
    let author: ActorNode?
  }

  struct Request: Decodable {
    let requestedReviewer: ActorNode?
  }

  struct Commit: Decodable {
    struct Inner: Decodable {
      struct Rollup: Decodable {
        let state: String?
        let contexts: Connection<CheckContext>?
      }

      let statusCheckRollup: Rollup?
    }

    let commit: Inner?
  }

  struct CheckContext: Decodable {
    let name: String?
    let status: String?
    let conclusion: String?
    let context: String?
    let state: String?
  }

  let kind: String?
  let title: String?
  let author: ActorNode?
  let createdAt: Date?
  let url: URL?
  let body: String?
  let labels: Connection<LabelNode>?
  let assignees: Connection<ActorNode>?
  let milestone: Title?
  let comments: Connection<TimelineNode>?
  let timelineItems: Connection<TimelineNode>?
  let baseRefName: String?
  let headRefName: String?
  let additions: Int?
  let deletions: Int?
  let changedFiles: Int?
  let mergeable: String?
  let reviewDecision: String?
  let latestReviews: Connection<Review>?
  let reviewRequests: Connection<Request>?
  let commits: Connection<Commit>?
  let isAnswered: Bool?
  let category: Title?

  var details: ThreadDetails? {
    guard kind != nil else { return nil }
    let conversation = timelineItems ?? comments
    let fetched = conversation?.fetchedCount ?? 0
    return ThreadDetails(
      author: author?.user,
      createdAt: createdAt,
      url: url,
      body: body ?? "",
      labels: labels?.items.map(\.label) ?? [],
      assignees: assignees?.items.compactMap(\.user) ?? [],
      milestone: milestone?.title,
      timeline: TimelineNode.timeline(of: conversation?.items ?? []),
      totalTimelineItems: conversation?.totalCount ?? fetched,
      hasOlderTimelineItems: (conversation?.totalCount ?? 0) > fetched,
      pullRequest: kind == "PullRequest" ? pullRequest : nil,
      discussion: kind == "Discussion" ? DiscussionDetails(category: category?.name, isAnswered: isAnswered ?? false) : nil
    )
  }

  private var pullRequest: PullRequestDetails {
    let requested = reviewRequests?.items.compactMap { $0.requestedReviewer?.user } ?? []
    let reviewed = latestReviews?.items.compactMap { review -> Reviewer? in
      guard let user = review.author?.user, let state = ReviewState(apiValue: review.state) else { return nil }
      let isRequested = requested.contains { $0.login == user.login }
      return isRequested || user.login == author?.login ? nil : Reviewer(user: user, state: state)
    }
    let decisions: [String: ReviewDecision] = [
      "APPROVED": .approved, "CHANGES_REQUESTED": .changesRequested, "REVIEW_REQUIRED": .reviewRequired,
    ]
    return PullRequestDetails(
      baseBranch: baseRefName ?? "",
      headBranch: headRefName ?? "",
      additions: additions ?? 0,
      deletions: deletions ?? 0,
      changedFiles: changedFiles ?? 0,
      reviewDecision: reviewDecision.flatMap { decisions[$0] },
      reviewers: (reviewed ?? []) + requested.map { Reviewer(user: $0, state: .requested) },
      checks: checks,
      hasConflicts: mergeable == "CONFLICTING"
    )
  }

  private var checks: CheckSummary? {
    guard let rollup = commits?.items.last?.commit?.statusCheckRollup, let state = rollup.state else { return nil }
    let contexts = rollup.contexts?.items ?? []
    let failed: Set<String> = ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "STALE"]
    let isPending = { (context: CheckContext) -> Bool in
      if let status = context.status { return status != "COMPLETED" }
      return context.state == "PENDING" || context.state == "EXPECTED"
    }
    let pending = contexts.filter(isPending)
    let done = contexts.filter { !isPending($0) }
    let failing = done.filter { failed.contains($0.conclusion ?? $0.state ?? "") }
    let passed = done.count { ($0.conclusion ?? $0.state) == "SUCCESS" }
    let rollupStates: [String: CheckState] = [
      "SUCCESS": .success, "FAILURE": .failure, "ERROR": .failure, "PENDING": .pending, "EXPECTED": .pending,
    ]
    return CheckSummary(
      state: rollupStates[state] ?? .pending,
      passed: passed,
      failing: failing.compactMap { $0.name ?? $0.context },
      pending: pending.compactMap { $0.name ?? $0.context }
    )
  }
}
