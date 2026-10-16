#if DEBUG
import AppKit
import Synchronization
import TidyCore

@MainActor
enum SettingsSnapshot {
    nonisolated static let output = UserDefaults.standard.string(forKey: "settingsSnapshot").map { URL(filePath: $0) }
    nonisolated static let scene = UserDefaults.standard.string(forKey: "settingsSnapshotScene")

    static let store: InboxStore? = {
        guard output != nil else { return nil }
        let directory = URL.temporaryDirectory.appending(path: "tidy-snapshot-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let account = #"{"user": {"login": "gustaferiksson"}, "scopes": ["notifications", "repo"]}"#
        try? Data(account.utf8).write(to: directory.appending(path: "account.json"))
        let muted = #"[{"id": "201", "title": "Nightly build failed for main", "repository": "octo/infra"}, {"id": "202", "title": "Roadmap for 2027", "repository": "octo/community"}]"#
        try? Data(muted.utf8).write(to: directory.appending(path: "muted.json"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SnapshotProtocol.self]
        return InboxStore(directory: directory, tokenStorage: MemoryTokenStorage(), session: GitHubClient.makeSession(configuration: configuration))
    }()

    static func capture(to output: URL) async {
        NSApp.setActivationPolicy(.prohibited)
        if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        URLProtocol.registerClass(SnapshotProtocol.self)
        if let store, scene != "signedOut", scene != "fineGrained" {
            try? await store.connect(token: "ghp_snapshot")
            _ = await store.refresh()
            store.rules = [
                FilterRule(conditions: [.author("dependabot[bot]"), .category(.pullRequest)]),
                FilterRule(conditions: [.notRepository("octo"), .reason(.subscribed)], action: .dontNotify),
                FilterRule(conditions: [.repository("octo/infra"), .category(.ci), .state(.closed)], action: .hideAndMarkDone),
            ]
            store.silencedReasons = [.subscribed, .ciActivity]
        }
        // SwiftUI rejects showSettingsWindow: sent from code ("use SettingsLink") but honours its own app-menu item.
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," })
        else { exit(1) }
        menu.performActionForItem(at: index)
        let settings = await SnapshotCapture.window { $0.identifier?.rawValue.contains("Settings") == true }
        SnapshotCapture.hideOffScreen(settings)
        let target = scene == "ruleEditor" ? await SnapshotCapture.window { $0.isSheet && $0.isVisible } : settings
        guard await SnapshotCapture.write(target, to: output) else { exit(1) }
        exit(0)
    }
}

private final class MemoryTokenStorage: TokenStorage {
    private let token = Mutex<String?>(nil)

    func read() -> String? { token.withLock { $0 } }
    func save(_ token: String) throws { self.token.withLock { $0 = token } }
    func delete() throws { token.withLock { $0 = nil } }
}

private final class SnapshotProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.isFileURL == false }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let (status, body) = Self.response(for: url)
        let headers = ["X-OAuth-Scopes": "notifications, repo", "Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        client?.urlProtocol(self, didReceive: response ?? HTTPURLResponse(), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func response(for url: URL) -> (Int, Data) {
        if url.path() == "/user" {
            let avatar = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")?.absoluteString ?? ""
            return (200, Data(#"{"login": "gustaferiksson", "avatar_url": "\#(avatar)"}"#.utf8))
        }
        guard url.path() == "/notifications" else { return (404, Data()) }
        let threads = [("octo/app", "PullRequest"), ("octo/infra", "CheckSuite"), ("acme/website", "Issue")].enumerated().map { index, entry in
            let owner = String(entry.0.split(separator: "/")[0])
            return NotificationThread(
                id: "\(100 + index)",
                reason: .reviewRequested,
                unread: true,
                updatedAt: .now,
                subject: Subject(title: "Snapshot thread \(index)", kind: SubjectKind(rawValue: entry.1)),
                repository: Repository(fullName: entry.0, owner: GitHubUser(login: owner), isPrivate: false, htmlURL: URL(string: "https://github.com/\(entry.0)")!)
            )
        }
        return (200, (try? GitHubClient.encoder.encode(threads)) ?? Data())
    }
}
#endif
