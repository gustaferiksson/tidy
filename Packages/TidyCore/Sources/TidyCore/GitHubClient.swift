import Foundation

public struct GitHubAccount: Codable, Hashable, Sendable {
  public var user: GitHubUser
  public var scopes: [String]

  public init(user: GitHubUser, scopes: [String]) {
    self.user = user
    self.scopes = scopes
  }
}

public struct NotificationsFetch: Sendable {
  public let threads: [NotificationThread]?
  public let isComplete: Bool
  public let lastModified: String?
  public let pollInterval: Duration
  public let scopes: [String]?
}

public struct GitHubClient: Sendable {
  public static let defaultBaseURL = URL(string: "https://api.github.com")!
  public static let threadLimit = 200
  public static let requiredScope = "repo"

  public static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  public static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  public let token: String
  public let baseURL: URL
  let session: URLSession
  let cache: ResponseCache?

  public init(token: String, session: URLSession = GitHubClient.makeSession(), baseURL: URL = defaultBaseURL, cache: ResponseCache? = nil) {
    self.token = token
    self.session = session
    self.baseURL = baseURL
    self.cache = cache
  }

  public static func makeSession(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }

  public static func since(now: Date, calendar: Calendar = .current) -> Date {
    calendar.date(byAdding: .day, value: -14, to: calendar.startOfDay(for: now))!
  }

  public func validate() async throws -> GitHubAccount {
    guard !token.hasPrefix("github_pat_") else { throw GitHubError.fineGrainedToken }
    let (data, response) = try await send(request(baseURL.appending(path: "user")))
    let user = try Self.decode(GitHubUser.self, from: data)
    let scopes = Self.scopes(in: response) ?? []
    guard scopes.contains(Self.requiredScope) else { throw GitHubError.missingScopes([Self.requiredScope]) }
    return GitHubAccount(user: user, scopes: scopes)
  }

  public func notifications(since: Date, ifModifiedSince: String?) async throws -> NotificationsFetch {
    let url = baseURL.appending(path: "notifications").appending(queryItems: [
      URLQueryItem(name: "all", value: "true"),
      URLQueryItem(name: "since", value: since.formatted(.iso8601)),
      URLQueryItem(name: "per_page", value: "50"),
    ])
    var first = request(url)
    first.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since")
    let (data, response) = try await send(first)
    let pollSeconds = response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(Int.init) ?? 60
    let pollInterval = Duration.seconds(max(60, pollSeconds))
    let scopes = Self.scopes(in: response)
    let lastModified = response.value(forHTTPHeaderField: "Last-Modified") ?? ifModifiedSince
    guard response.statusCode != 304 else {
      return NotificationsFetch(threads: nil, isComplete: true, lastModified: lastModified, pollInterval: pollInterval, scopes: scopes)
    }
    // A 200 to a conditional request lists only threads changed since If-Modified-Since, not the whole inbox.
    guard ifModifiedSince == nil else { return try await notifications(since: since, ifModifiedSince: nil) }
    var threads = try Self.decode([NotificationThread].self, from: data)
    var next = Self.nextPage(in: response)
    while let page = next, threads.count < Self.threadLimit {
      let (data, response) = try await send(request(page))
      threads += try Self.decode([NotificationThread].self, from: data)
      next = Self.nextPage(in: response)
    }
    return NotificationsFetch(
      threads: Array(threads.prefix(Self.threadLimit)),
      isComplete: next == nil && threads.count <= Self.threadLimit,
      lastModified: lastModified,
      pollInterval: pollInterval,
      scopes: scopes
    )
  }

  public func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
    let cached = await cache?.entry(for: url)
    var request = request(url)
    request.setValue(cached?.etag, forHTTPHeaderField: "If-None-Match")
    let (data, response) = try await send(request)
    if response.statusCode == 304, let cached { return try Self.decode(type, from: cached.data) }
    let decoded = try Self.decode(type, from: data)
    if let etag = response.value(forHTTPHeaderField: "ETag") {
      await cache?.store(ResponseCache.Entry(etag: etag, data: data), for: url)
    }
    return decoded
  }

  public func markRead(threadID: String) async throws {
    try await send(request(baseURL.appending(path: "notifications/threads/\(threadID)"), method: "PATCH"))
  }

  public func remove(threadID: String) async throws {
    try await send(request(baseURL.appending(path: "notifications/threads/\(threadID)"), method: "DELETE"))
  }

  public func markAllRead(lastReadAt: Date, repository: String? = nil) async throws {
    let path = repository.map { "repos/\($0)/notifications" } ?? "notifications"
    let body: [String: Any] = ["last_read_at": lastReadAt.formatted(.iso8601), "read": true]
    try await send(request(baseURL.appending(path: path), method: "PUT", body: body))
  }

  public func mute(threadID: String) async throws {
    try await send(request(baseURL.appending(path: "notifications/threads/\(threadID)/subscription"), method: "PUT", body: ["ignored": true]))
  }

  public func unmute(threadID: String) async throws {
    try await send(request(baseURL.appending(path: "notifications/threads/\(threadID)/subscription"), method: "PUT", body: ["ignored": false]))
  }

  private func request(_ url: URL, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    if let body {
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  @discardableResult
  private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let result: (Data, URLResponse)
    do {
      result = try await session.data(for: request)
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch is URLError {
      throw GitHubError.offline
    }
    guard let response = result.1 as? HTTPURLResponse else { throw GitHubError.offline }
    if let error = GitHubError.classify(response) { throw error }
    return (result.0, response)
  }

  private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw GitHubError.decoding
    }
  }

  static func scopes(in response: HTTPURLResponse) -> [String]? {
    response.value(forHTTPHeaderField: "X-OAuth-Scopes").map {
      $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
  }

  private static func nextPage(in response: HTTPURLResponse) -> URL? {
    let link = response.value(forHTTPHeaderField: "Link") ?? ""
    let next = link.split(separator: ",").first { $0.contains("rel=\"next\"") }
    let target = next?.split(separator: ";").first?.trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
    return target.flatMap { URL(string: $0) }
  }
}
