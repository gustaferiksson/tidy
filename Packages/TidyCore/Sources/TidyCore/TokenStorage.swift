import Foundation
import Security

public protocol TokenStorage: Sendable {
  func read() throws -> String?
  func save(_ token: String) throws
  func delete() throws
}

public struct KeychainError: Error, Equatable, Sendable {
  public let status: OSStatus
}

public struct KeychainTokenStore: TokenStorage {
  public let service: String
  public let account: String

  public init(service: String = "dev.gustaf.tidy", account: String = "github-token") {
    self.service = service
    self.account = account
  }

  private func query(dataProtection: Bool) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseDataProtectionKeychain as String: dataProtection,
    ]
  }

  public func read() throws -> String? {
    for dataProtection in [true, false] {
      var result: AnyObject?
      let lookup = query(dataProtection: dataProtection).merging([
        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
      ]) { $1 }
      let status = SecItemCopyMatching(lookup as CFDictionary, &result)
      if status == errSecItemNotFound || status == errSecMissingEntitlement { continue }
      guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
      return String(data: data, encoding: .utf8)
    }
    return nil
  }

  public func save(_ token: String) throws {
    // The data protection keychain needs an application identifier, which ad-hoc and unsigned builds lack.
    let status = upsert(token, dataProtection: true)
    let fallback = status == errSecMissingEntitlement ? upsert(token, dataProtection: false) : status
    guard fallback == errSecSuccess else { throw KeychainError(status: fallback) }
  }

  public func delete() throws {
    for dataProtection in [true, false] {
      let status = SecItemDelete(query(dataProtection: dataProtection) as CFDictionary)
      guard [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement].contains(status) else {
        throw KeychainError(status: status)
      }
    }
  }

  private func upsert(_ token: String, dataProtection: Bool) -> OSStatus {
    let item = query(dataProtection: dataProtection)
    let value = [kSecValueData as String: Data(token.utf8)]
    let status = SecItemUpdate(item as CFDictionary, value as CFDictionary)
    guard status == errSecItemNotFound else { return status }
    let added = item.merging(value) { $1 }.merging([kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { $1 }
    return SecItemAdd(added as CFDictionary, nil)
  }
}
