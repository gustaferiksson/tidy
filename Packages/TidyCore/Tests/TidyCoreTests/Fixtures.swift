import Foundation

@testable import TidyCore

enum Fixture {
  static func data(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
  }

  static var threads: [NotificationThread] {
    try! GitHubClient.decoder.decode([NotificationThread].self, from: data("notifications"))
  }

  static func thread(_ id: String) -> NotificationThread {
    threads.first { $0.id == id }!
  }
}
