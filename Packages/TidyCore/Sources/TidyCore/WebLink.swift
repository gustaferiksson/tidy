import Foundation

public enum WebLink {
  public static func url(for thread: NotificationThread, details: SubjectDetails?) -> URL {
    if let activityURL = details?.activity?.htmlURL ?? details?.latestComment?.htmlURL { return activityURL }
    let repo = thread.repository.htmlURL
    guard let subjectURL = thread.subject.url else { return fallback(for: thread.subject.kind, repository: repo) }
    guard let page = details?.htmlURL ?? webURL(forAPI: subjectURL) else {
      return thread.subject.kind == .release ? repo.appending(path: "releases") : repo
    }
    guard let commentURL = thread.subject.latestCommentURL, commentURL != subjectURL,
      let anchor = anchor(forCommentAPI: commentURL)
    else { return page }
    return URL(string: page.absoluteString + "#" + anchor) ?? page
  }

  public static func fallback(for kind: SubjectKind, repository: URL) -> URL {
    switch kind {
    case .checkSuite, .workflowRun: repository.appending(path: "actions")
    case .dependabotAlerts: repository.appending(path: "security/dependabot")
    case .secretScanningAlert: repository.appending(path: "security/secret-scanning")
    case .repositoryAdvisory: repository.appending(path: "security/advisories")
    case .discussion: repository.appending(path: "discussions")
    default: repository
    }
  }

  public static func webURL(forAPI url: URL) -> URL? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard url.host() == "api.github.com", parts.count == 5, parts[0] == "repos" else { return nil }
    let (owner, repo, kind, identifier) = (parts[1], parts[2], parts[3], parts[4])
    let webKind: String? =
      switch kind {
      case "pulls": "pull"
      case "issues": "issues"
      case "commits": "commit"
      case "discussions": "discussions"
      default: nil
      }
    guard let webKind else { return nil }
    return URL(string: "https://github.com/\(owner)/\(repo)/\(webKind)/\(identifier)")
  }

  public static func anchor(forCommentAPI url: URL) -> String? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 5, parts[0] == "repos", let id = parts.last, Int(id) != nil else { return nil }
    let tail = parts.dropFirst(3).dropLast().joined(separator: "/")
    if tail == "issues/comments" { return "issuecomment-\(id)" }
    if tail == "pulls/comments" { return "discussion_r\(id)" }
    if tail == "comments" { return "commitcomment-\(id)" }
    return nil
  }
}
