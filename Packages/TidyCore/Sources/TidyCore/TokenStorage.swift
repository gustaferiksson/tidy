import Foundation
import Security

public protocol TokenStorage: Sendable {
  func read() -> String?
  func save(_ token: String) throws
  func delete() throws
}

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

public struct KeychainTokenStore: TokenStorage {
  public let service: String
  public let account: String

  public init(service: String = "dev.gustaf.Tidy", account: String = "github-token") {
    self.service = service
    self.account = account
  }

  private var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  public func read() -> String? {
    var result: AnyObject?
    let lookup = query.merging([kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]) { $1 }
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func save(_ token: String) throws {
    try delete()
    let item = query.merging([
      kSecValueData as String: Data(token.utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]) { $1 }
    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  public func delete() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
  }
}
