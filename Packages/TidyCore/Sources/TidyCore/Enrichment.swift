import Foundation

extension GitHubClient {
  public func details(for thread: NotificationThread, previous: SubjectDetails? = nil) async throws -> SubjectDetails {
    let repo = baseURL.appending(path: "repos/\(thread.repository.fullName)")
    let kind = thread.subject.kind
    let open = [URLQueryItem(name: "state", value: "open"), URLQueryItem(name: "per_page", value: "100")]
    if kind == .dependabotAlerts {
      let alerts = try await get([AlertPayload].self, from: repo.appending(path: "dependabot/alerts").appending(queryItems: open))
      return SubjectDetails(state: .open, alerts: alerts.map(\.alert))
    }
    if kind == .secretScanningAlert {
      let alerts = try await get([AlertPayload].self, from: repo.appending(path: "secret-scanning/alerts").appending(queryItems: open))
      return SubjectDetails(state: .open, alerts: alerts.map(\.alert))
    }
    if kind == .repositoryAdvisory {
      let advisories = try await get([AlertPayload].self, from: repo.appending(path: "security-advisories"))
      return SubjectDetails(state: .open, alerts: advisories.filter { $0.state != "closed" }.map(\.alert))
    }
    guard let subjectURL = thread.subject.url else {
      return SubjectDetails(state: kind == .discussion ? .open : nil)
    }
    let payload = try await get(SubjectPayload.self, from: subjectURL)
    let commentURL = thread.subject.latestCommentURL.flatMap { $0 == subjectURL ? nil : $0 }
    let comment: Comment? =
      if let commentURL, previous?.latestComment?.apiURL == commentURL {
        previous?.latestComment
      } else if let commentURL {
        try? await get(CommentPayload.self, from: commentURL).comment(apiURL: commentURL)
      } else if kind == .pullRequest {
        try? await latestReview(on: subjectURL, near: thread.updatedAt)
      } else {
        nil
      }
    return SubjectDetails(
      state: payload.state(for: kind),
      author: payload.user ?? payload.author,
      body: payload.body ?? payload.commit?.message,
      htmlURL: payload.htmlURL,
      latestComment: comment
    )
  }

  private func latestReview(on pullURL: URL, near updatedAt: Date) async throws -> Comment? {
    let reviews = try await get(
      [ReviewPayload].self, from: pullURL.appending(path: "reviews").appending(queryItems: [URLQueryItem(name: "per_page", value: "100")]))
    let latest = reviews.last { review in
      guard let state = ReviewState(apiValue: review.state), state != .dismissed else { return false }
      return state != .commented || !(review.body ?? "").isEmpty
    }
    // GitHub bumps the thread's updated_at a few seconds after the review it reports.
    guard let latest, let state = ReviewState(apiValue: latest.state), let submittedAt = latest.submittedAt,
      submittedAt >= updatedAt.addingTimeInterval(-120)
    else { return nil }
    return Comment(
      apiURL: pullURL.appending(path: "reviews/\(latest.id)"), author: latest.user, body: latest.body ?? "", htmlURL: latest.htmlURL,
      review: state)
  }
}

private struct SubjectPayload: Decodable {
  struct CommitPart: Decodable {
    let message: String?
  }

  let state: String?
  let stateReason: String?
  let draft: Bool?
  let merged: Bool?
  let answerChosenAt: String?
  let user: GitHubUser?
  let author: GitHubUser?
  let body: String?
  let htmlURL: URL?
  let commit: CommitPart?

  enum CodingKeys: String, CodingKey {
    case state, draft, merged, user, author, body, commit
    case stateReason = "state_reason"
    case answerChosenAt = "answer_chosen_at"
    case htmlURL = "html_url"
  }

  func state(for kind: SubjectKind) -> SubjectState? {
    if kind == .pullRequest {
      if merged == true { return .merged }
      if state == "closed" { return .closed }
      return draft == true ? .draft : .open
    }
    if kind == .issue {
      guard state == "closed" else { return .open }
      return stateReason == "not_planned" ? .notPlanned : .closed
    }
    if kind == .discussion { return answerChosenAt == nil ? .open : .answered }
    return nil
  }
}

private struct CommentPayload: Decodable {
  let user: GitHubUser?
  let body: String?
  let htmlURL: URL?

  enum CodingKeys: String, CodingKey {
    case user, body
    case htmlURL = "html_url"
  }

  func comment(apiURL: URL) -> Comment {
    Comment(apiURL: apiURL, author: user, body: body ?? "", htmlURL: htmlURL)
  }
}

private struct ReviewPayload: Decodable {
  let id: Int
  let user: GitHubUser?
  let body: String?
  let state: String?
  let htmlURL: URL?
  let submittedAt: Date?

  enum CodingKeys: String, CodingKey {
    case id, user, body, state
    case htmlURL = "html_url"
    case submittedAt = "submitted_at"
  }
}

private struct AlertPayload: Decodable {
  struct Advisory: Decodable {
    let ghsaID: String?
    let summary: String?
    let severity: String?

    enum CodingKeys: String, CodingKey {
      case summary, severity
      case ghsaID = "ghsa_id"
    }
  }

  struct Vulnerability: Decodable {
    let severity: String?
  }

  struct Dependency: Decodable {
    struct Package: Decodable {
      let name: String?
    }

    let package: Package?
  }

  let number: Int?
  let state: String?
  let ghsaID: String?
  let summary: String?
  let severity: String?
  let secretTypeDisplayName: String?
  let htmlURL: URL?
  let dependency: Dependency?
  let securityAdvisory: Advisory?
  let securityVulnerability: Vulnerability?

  enum CodingKeys: String, CodingKey {
    case number, state, summary, severity, dependency
    case ghsaID = "ghsa_id"
    case secretTypeDisplayName = "secret_type_display_name"
    case htmlURL = "html_url"
    case securityAdvisory = "security_advisory"
    case securityVulnerability = "security_vulnerability"
  }

  var alert: SecurityAlert {
    let advisoryID = securityAdvisory?.ghsaID ?? ghsaID
    return SecurityAlert(
      id: number.map(String.init) ?? advisoryID ?? htmlURL?.absoluteString ?? summary ?? "alert",
      package: dependency?.package?.name,
      severity: Severity(apiValue: securityAdvisory?.severity ?? securityVulnerability?.severity ?? severity),
      summary: securityAdvisory?.summary ?? summary ?? secretTypeDisplayName ?? "Security alert",
      advisoryID: advisoryID,
      htmlURL: htmlURL
    )
  }
}
