import AppKit
import TidyCore
import UserNotifications

@MainActor
final class Banners: NSObject {
    private static let threadCategory = "thread"
    private static let summaryCategory = "summary"
    private static let summaryIdentifier = "summary"

    private let store: InboxStore
    private let panel: PanelController
    private let center = UNUserNotificationCenter.current()
    private var eventsTask: Task<Void, Never>?

    init(store: InboxStore, panel: PanelController) {
        self.store = store
        self.panel = panel
    }

    func start() {
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: "quickLook", title: "Quick Look", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "eye")),
            UNNotificationAction(identifier: "markRead", title: "Mark as Read", options: [], icon: UNNotificationActionIcon(systemImageName: "envelope.open")),
            UNNotificationAction(identifier: "done", title: "Done", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark")),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.threadCategory, actions: actions, intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "New GitHub activity"),
            UNNotificationCategory(identifier: Self.summaryCategory, actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "New GitHub activity"),
        ])
        eventsTask = Task { [weak self, events = store.events] in
            for await event in events { self?.handle(event) }
        }
        requestAuthorizationOnceConnected()
    }

    private func requestAuthorizationOnceConnected() {
        let isConnected = withObservationTracking {
            store.isSignedIn && store.hasLoaded
        } onChange: {
            Task { @MainActor [weak self] in self?.requestAuthorizationOnceConnected() }
        }
        guard isConnected else { return }
        Task { [center] in _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    private func handle(_ event: InboxEvent) {
        if case .withdraw(let ids) = event {
            center.removeDeliveredNotifications(withIdentifiers: ids)
            return
        }
        guard !panel.isOpen else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        if case .summary(let count) = event {
            content.title = "\(count) new notifications"
            content.categoryIdentifier = Self.summaryCategory
            center.add(UNNotificationRequest(identifier: Self.summaryIdentifier, content: content, trigger: nil))
            return
        }
        guard case .newThread(let item) = event else { return }
        let repository = item.thread.repository.fullName
        content.title = item.title
        content.subtitle = "\(repository) · \(item.thread.reason.title)"
        if let comment = item.details?.latestComment, let review = comment.review {
            let action = "\(review.title) by \(comment.author?.login ?? "a reviewer")"
            let note = MarkdownView.plainFirstLine(of: comment.body)
            content.body = note.isEmpty ? action : "\(action): \(note)"
        } else {
            content.body = item.previewMarkdown.map(MarkdownView.plainFirstLine) ?? ""
        }
        content.threadIdentifier = repository
        content.categoryIdentifier = Self.threadCategory
        content.userInfo = ["url": item.webURL.absoluteString]
        center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: nil))
    }

    private func respond(to action: String, threadID: String, url: URL?) {
        if threadID == Self.summaryIdentifier {
            panel.open()
            return
        }
        if action == "quickLook" {
            panel.open(quickLook: threadID)
        } else if action == "markRead" {
            store.markRead([threadID])
        } else if action == "done" {
            store.markDone([threadID])
        } else if action == UNNotificationDefaultActionIdentifier, let url, url.isGitHubWeb {
            NSWorkspace.shared.open(url)
            store.markRead([threadID])
        }
    }
}

extension Banners: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await panel.isOpen ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let threadID = response.notification.request.identifier
        let url = (response.notification.request.content.userInfo["url"] as? String).flatMap(URL.init(string:))
        await respond(to: action, threadID: threadID, url: url)
    }
}
