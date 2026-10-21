import Foundation

public struct Activity: Codable, Hashable, Sendable {
  public enum Kind: Codable, Hashable, Sendable {
    case reviewed(ReviewState)
    case commented
    case pushed(commits: Int?)
    case forcePushed
    case requestedReview(from: String?)
    case assigned(to: String)
    case merged, closed, reopened, readyForReview, opened, published
  }

  public var actor: String
  public var kind: Kind
  public var detail: String?
  public var htmlURL: URL?

  public init(actor: String, kind: Kind, detail: String? = nil, htmlURL: URL? = nil) {
    self.actor = actor
    self.kind = kind
    self.detail = detail
    self.htmlURL = htmlURL
  }

  public var headline: String {
    let who = actor == "you" ? "You" : actor
    return switch kind {
    case .reviewed(.approved): "Approved by \(actor)"
    case .reviewed(.changesRequested): "Changes requested by \(actor)"
    case .reviewed, .commented: "\(who) commented"
    case .pushed(commits: 1): "\(who) pushed a commit"
    case .pushed(commits: let count?): "\(who) pushed \(count) commits"
    case .pushed(commits: nil): "\(who) pushed commits"
    case .forcePushed: "\(who) force-pushed"
    case .requestedReview(from: "you"): "\(who) requested your review"
    case .requestedReview(from: let reviewer?): "\(who) requested review from \(reviewer)"
    case .requestedReview(from: nil): "\(who) requested a review"
    case .assigned(to: let assignee): "Assigned to \(assignee) by \(actor)"
    case .merged: "Merged by \(actor)"
    case .closed: "Closed by \(actor)"
    case .reopened: "Reopened by \(actor)"
    case .readyForReview: "Marked ready for review by \(actor)"
    case .opened: "Opened by \(actor)"
    case .published: "Published by \(actor)"
    }
  }
}

extension GitHubClient {
  static let timelineLimit = 10

  func recentActivity(for thread: NotificationThread) async -> Activity? {
    let parts = thread.repository.fullName.split(separator: "/", maxSplits: 1).map(String.init)
    guard [.pullRequest, .issue].contains(thread.subject.kind), let number = thread.number, parts.count == 2 else { return nil }
    let variables: [String: Any] = ["owner": parts[0], "name": parts[1], "number": number]
    let data = try? await graphQL(ActivityData.self, query: Self.activityQuery, variables: variables) { $0 }
    return data?.activity(near: thread.updatedAt)
  }

  static let activityQuery = {
    let shared = """
      ... on IssueComment { author { login } body createdAt url }
      ... on ClosedEvent { actor { login } createdAt }
      ... on ReopenedEvent { actor { login } createdAt }
      ... on AssignedEvent { actor { login } createdAt assignee { ... on User { login } } }
      """
    return """
      query($owner: String!, $name: String!, $number: Int!) {
        viewer { login }
        repository(owner: $owner, name: $name) {
          issueOrPullRequest(number: $number) {
            ... on PullRequest {
              createdAt author { login }
              timelineItems(last: \(timelineLimit), itemTypes: [PULL_REQUEST_COMMIT, ISSUE_COMMENT, PULL_REQUEST_REVIEW, REVIEW_REQUESTED_EVENT, MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT, HEAD_REF_FORCE_PUSHED_EVENT, READY_FOR_REVIEW_EVENT, ASSIGNED_EVENT]) { nodes {
                type: __typename
                ... on PullRequestCommit { commit { committedDate messageHeadline author { name user { login } } } }
                ... on PullRequestReview { author { login } body createdAt url state }
                ... on ReviewRequestedEvent { actor { login } createdAt requestedReviewer { ... on User { login } } }
                ... on MergedEvent { actor { login } createdAt }
                ... on HeadRefForcePushedEvent { actor { login } createdAt }
                ... on ReadyForReviewEvent { actor { login } createdAt }
                \(shared)
              } }
            }
            ... on Issue {
              createdAt author { login }
              timelineItems(last: \(timelineLimit), itemTypes: [ISSUE_COMMENT, CLOSED_EVENT, REOPENED_EVENT, ASSIGNED_EVENT]) { nodes {
                type: __typename
                \(shared)
              } }
            }
          }
        }
      }
      """
  }()
}

private struct ActivityData: Decodable {
  struct Subject: Decodable {
    let createdAt: Date?
    let author: ActorNode?
    let timelineItems: Connection<TimelineNode>?
  }

  struct Repository: Decodable {
    let issueOrPullRequest: Subject?
  }

  let viewer: ActorNode?
  let repository: Repository?

  func activity(near updatedAt: Date) -> Activity? {
    guard let subject = repository?.issueOrPullRequest else { return nil }
    let display = { (login: String) in login == viewer?.login ? "you" : login }
    let items = subject.timelineItems?.items ?? []
    let events: [(date: Date, activity: Activity)] = items.compactMap { item in
      guard let date = item.createdAt, (-120...120).contains(date.timeIntervalSince(updatedAt)), let activity = item.activity(as: display)
      else { return nil }
      return (date, activity)
    }
    let commits = items.reversed().prefix { $0.type == "PullRequestCommit" }.compactMap(\.commit)
    let pushes: [(date: Date, activity: Activity)] =
      commits.first.flatMap { newest in
        guard let date = newest.committedDate, let pusher = newest.author?.user?.login ?? newest.author?.name,
          date > subject.createdAt ?? .distantPast, (-3600...120).contains(date.timeIntervalSince(updatedAt))
        else { return nil }
        let count = commits.prefix { ($0.author?.user?.login ?? $0.author?.name) == pusher }.count
        let kind = Activity.Kind.pushed(commits: count == GitHubClient.timelineLimit ? nil : count)
        return [(date, Activity(actor: display(pusher), kind: kind, detail: newest.messageHeadline))]
      } ?? []
    let preferred: [Activity.Kind] = [.merged, .requestedReview(from: "you"), .assigned(to: "you")]
    let rank = { (candidate: (date: Date, activity: Activity)) in (candidate.date, preferred.contains(candidate.activity.kind) ? 1 : 0) }
    if let newest = (events + pushes).reversed().max(by: { rank($0) < rank($1) }) { return newest.activity }
    guard let createdAt = subject.createdAt, (-120...120).contains(createdAt.timeIntervalSince(updatedAt)), let author = subject.author?.login
    else { return nil }
    return Activity(actor: display(author), kind: .opened)
  }
}

extension TimelineNode {
  func activity(as display: (String) -> String) -> Activity? {
    guard let login = (actor ?? author)?.login else { return nil }
    let who = display(login)
    let events: [String: Activity.Kind] = [
      "MergedEvent": .merged, "ClosedEvent": .closed, "ReopenedEvent": .reopened, "HeadRefForcePushedEvent": .forcePushed,
      "ReadyForReviewEvent": .readyForReview,
    ]
    if let kind = type.flatMap({ events[$0] }) { return Activity(actor: who, kind: kind) }
    if type == "IssueComment" { return Activity(actor: who, kind: .commented, detail: body, htmlURL: url) }
    if type == "ReviewRequestedEvent" { return Activity(actor: who, kind: .requestedReview(from: requestedReviewer?.login.map(display))) }
    if type == "AssignedEvent", let assignee = assignee?.login { return Activity(actor: who, kind: .assigned(to: display(assignee))) }
    guard type == "PullRequestReview", let review = ReviewState(apiValue: state), review != .dismissed, review != .commented || !(body ?? "").isEmpty
    else { return nil }
    return Activity(actor: who, kind: .reviewed(review), detail: body, htmlURL: url)
  }
}
