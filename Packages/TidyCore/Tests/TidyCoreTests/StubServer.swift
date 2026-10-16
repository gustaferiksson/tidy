import Foundation
import Synchronization

@testable import TidyCore

struct StubResponse: Sendable {
  var status: Int
  var headers: [String: String] = [:]
  var body = Data()

  static func json(_ fixture: String, status: Int = 200, headers: [String: String] = [:]) -> StubResponse {
    StubResponse(status: status, headers: headers, body: Fixture.data(fixture))
  }

  static func encoded(_ value: some Encodable, headers: [String: String] = [:]) -> StubResponse {
    StubResponse(status: 200, headers: headers, body: try! GitHubClient.encoder.encode(value))
  }

  static let offline = StubResponse(status: 0)
}

struct RecordedRequest: Sendable {
  let method: String
  let url: URL
  let headers: [String: String]
  let body: Data?

  var path: String { url.path() }

  var json: [String: Any]? {
    body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }
}

final class StubServer: Sendable {
  typealias Handler = @Sendable (RecordedRequest) -> StubResponse

  let token = "test-\(UUID().uuidString)"
  private let routes = Mutex<[String: Handler]>([:])
  private let recorded = Mutex<[RecordedRequest]>([])

  init() {
    stubRegistry.withLock { $0[token] = self }
  }

  var session: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubProtocol.self]
    return GitHubClient.makeSession(configuration: configuration)
  }

  var client: GitHubClient { GitHubClient(token: token, session: session) }

  var requests: [RecordedRequest] { recorded.withLock { $0 } }

  func on(_ method: String, _ path: String, handler: @escaping Handler) {
    routes.withLock { $0["\(method) \(path)"] = handler }
  }

  func on(_ method: String, _ path: String, respond response: StubResponse) {
    on(method, path) { _ in response }
  }

  func handle(_ request: RecordedRequest) -> StubResponse {
    recorded.withLock { $0.append(request) }
    let handler = routes.withLock { $0["\(request.method) \(request.path)"] }
    return handler?(request) ?? StubResponse(status: 404)
  }
}

let stubRegistry = Mutex<[String: StubServer]>([:])

final class StubProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func stopLoading() {}

  override func startLoading() {
    let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
    let body = request.httpBody ?? request.httpBodyStream.map { stream in
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
      }
      return data
    }
    let recorded = RecordedRequest(
      method: request.httpMethod ?? "GET", url: request.url!,
      headers: request.allHTTPHeaderFields ?? [:], body: body)
    guard let server = stubRegistry.withLock({ $0[token] }) else {
      client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
      return
    }
    let stub = server.handle(recorded)
    guard stub.status != 0 else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: stub.body)
    client?.urlProtocolDidFinishLoading(self)
  }
}

func makeThreads(count: Int, startingAt start: Int = 1, from date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> [NotificationThread] {
  let template = Fixture.thread("101")
  return (start..<(start + count)).map { index in
    NotificationThread(
      id: "\(index)", reason: template.reason, unread: true,
      updatedAt: date.addingTimeInterval(-Double(index) * 60), subject: template.subject, repository: template.repository)
  }
}
