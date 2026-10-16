import Foundation
import Testing

@testable import TidyCore

@Suite(.enabled(if: ProcessInfo.processInfo.environment["TIDY_KEYCHAIN_TESTS"] != nil))
struct KeychainTests {
  let store = KeychainTokenStore(service: "dev.gustaf.Tidy.tests.\(UUID().uuidString)", account: "test-token")

  @Test func savesUpdatesAndDeletes() throws {
    defer { try? store.delete() }
    #expect(try store.read() == nil)
    try store.save("first")
    #expect(try store.read() == "first")
    try store.save("second")
    #expect(try store.read() == "second")
    try store.delete()
    #expect(try store.read() == nil)
  }
}
