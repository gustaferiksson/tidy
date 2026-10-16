import CryptoKit
import Foundation

public actor ResponseCache {
  public struct Entry: Codable, Sendable {
    public let etag: String
    public let data: Data
  }

  private let directory: URL

  public init(directory: URL) {
    self.directory = directory
  }

  public func entry(for url: URL) -> Entry? {
    guard let data = try? Data(contentsOf: file(for: url)) else { return nil }
    return try? JSONDecoder().decode(Entry.self, from: data)
  }

  public func store(_ entry: Entry, for url: URL) {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? JSONEncoder().encode(entry).write(to: file(for: url), options: .atomic)
  }

  public func removeAll() {
    try? FileManager.default.removeItem(at: directory)
  }

  private func file(for url: URL) -> URL {
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    return directory.appending(path: digest.map { String(format: "%02x", $0) }.joined() + ".json")
  }
}
