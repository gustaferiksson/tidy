import Foundation

public enum MarkAllReadTarget: Codable, Hashable, Sendable {
  case everything(lastReadAt: Date)
  case repository(String, lastReadAt: Date)
  case visibleThreads
}

public enum PendingAction: Codable, Hashable, Sendable {
  case markRead
  case done
  case mute
  case markAllRead(MarkAllReadTarget)
}

public struct PendingChange: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let action: PendingAction
  public let items: [InboxItem]

  public init(id: UUID = UUID(), action: PendingAction, items: [InboxItem]) {
    self.id = id
    self.action = action
    self.items = items
  }

  public var threadIDs: [String] { items.map(\.id) }

  public var message: String {
    let count = items.count
    switch action {
    case .markRead: return "Marked \(count) as read"
    case .done: return "Marked \(count) as done"
    case .mute: return count == 1 ? "Muted thread" : "Muted \(count) threads"
    case .markAllRead: return "Marked all as read"
    }
  }

  func restricted(to ids: Set<String>) -> PendingChange {
    PendingChange(id: id, action: action, items: items.filter { ids.contains($0.id) })
  }
}

public struct ActionFailure: Hashable, Sendable {
  public let changes: [PendingChange]

  public var count: Int { changes.reduce(0) { $0 + $1.items.count } }
  public var message: String { count == 1 ? "Couldn't update 1 notification" : "Couldn't update \(count) notifications" }
}

public struct MutedThread: Codable, Hashable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let repository: String
}

public struct InboxScope: Hashable, Sendable {
  public var participatingOnly: Bool
  public var repository: String?

  public init(participatingOnly: Bool = false, repository: String? = nil) {
    self.participatingOnly = participatingOnly
    self.repository = repository
  }

  public var isActive: Bool { participatingOnly || repository != nil }

  public func contains(_ item: InboxItem) -> Bool {
    (!participatingOnly || item.thread.reason.group == .participating)
      && (repository.map { $0 == item.thread.repository.fullName } ?? true)
  }
}

public enum SyncIssue: Hashable, Sendable {
  case offline
  case rateLimited(resumesAt: Date)
  case ssoRequired(organization: String?, url: URL?)
  case notResponding
  case unauthorized
  case missingScope
  case keychainUnavailable
}

public enum InboxEvent: Hashable, Sendable {
  case newThread(InboxItem)
  case summary(count: Int)
  case withdraw(threadIDs: [String])
}
