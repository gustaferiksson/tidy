import Foundation

public enum GitHubError: Error, Equatable, Sendable {
  case fineGrainedToken
  case unauthorized
  case missingScopes([String])
  case ssoRequired(organization: String?, url: URL?)
  case rateLimited(resetsAt: Date)
  case offline
  case forbidden
  case notFound
  case server(status: Int)
  case unexpectedStatus(Int)
  case decoding

  public var message: String {
    switch self {
    case .fineGrainedToken: "Fine-grained tokens can't read notifications. Use a classic token."
    case .unauthorized: "Your GitHub token is no longer valid"
    case .missingScopes(let scopes): "Token needs the \(scopes.joined(separator: ", ")) scope"
    case .ssoRequired(let organization, _): "Authorize token for \(organization ?? "your organization")"
    case .rateLimited: "GitHub rate limit"
    case .offline: "Can't reach GitHub"
    case .forbidden: "GitHub refused the request"
    case .notFound: "Not found on GitHub"
    case .server, .unexpectedStatus, .decoding: "GitHub isn't responding"
    }
  }

  public static func classify(_ response: HTTPURLResponse, now: Date = .now) -> GitHubError? {
    let status = response.statusCode
    if (200..<300).contains(status) || status == 304 { return nil }
    if status == 401 { return .unauthorized }
    if status == 403 || status == 429 {
      if let sso = response.value(forHTTPHeaderField: "X-GitHub-SSO") {
        let url = sso.components(separatedBy: "url=").dropFirst().first.flatMap {
          URL(string: $0.trimmingCharacters(in: .whitespaces))
        }
        let parts = url?.pathComponents ?? []
        let organization = parts.firstIndex(of: "orgs").flatMap { parts.indices.contains($0 + 1) ? parts[$0 + 1] : nil }
        return .ssoRequired(organization: organization, url: url)
      }
      if let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
        return .rateLimited(resetsAt: now.addingTimeInterval(retryAfter))
      }
      if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
        let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init)
        return .rateLimited(resetsAt: reset.map(Date.init(timeIntervalSince1970:)) ?? now.addingTimeInterval(60))
      }
      return status == 429 ? .rateLimited(resetsAt: now.addingTimeInterval(60)) : .forbidden
    }
    if status == 404 { return .notFound }
    if (500..<600).contains(status) { return .server(status: status) }
    return .unexpectedStatus(status)
  }
}
