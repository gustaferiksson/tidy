#if DEBUG
import AppKit
import SwiftUI
import TidyCore

@MainActor
enum InboxSnapshot {
    enum Fixture: String {
        case populated, empty, signedOut
    }

    nonisolated static let output = UserDefaults.standard.string(forKey: "inboxSnapshot").map { URL(filePath: $0) }

    static func makeStore(_ fixture: Fixture, commitDelay: Duration = .zero) -> InboxStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return InboxStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "tidy-inbox-snapshot-\(UUID().uuidString)"),
            tokenStorage: FixtureTokenStorage(token: fixture == .signedOut ? nil : fixture.rawValue),
            session: GitHubClient.makeSession(configuration: configuration),
            commitDelay: commitDelay,
            networkPaths: AsyncStream { $0.yield(true) }
        )
    }

    static func capture(to directory: URL, updater: AppUpdater) async {
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let defaults = UserDefaults(suiteName: "dev.gustaf.Tidy.inboxSnapshot") ?? .standard
        defaults.removePersistentDomain(forName: "dev.gustaf.Tidy.inboxSnapshot")
        defaults.set(true, forKey: "showsAllThreads")

        let populated = makeStore(.populated)
        await load(populated)
        populated.markDone(["9", "10"])
        try? await Task.sleep(for: .milliseconds(300))
        let filtered = makeStore(.populated, commitDelay: .seconds(600))
        await load(filtered)
        filtered.markDone(["10"])
        filtered.scope.repository = "tinecli/tidy"
        filtered.markDone(["6"])
        let empty = makeStore(.empty)
        await load(empty)
        let scenarios: [(String, InboxStore, String?, String?)] = [
            ("populated", populated, nil, nil),
            ("hover", populated, nil, "1"),
            ("hoverselected", populated, nil, "2"),
            ("quicklook", populated, "1", nil),
            ("quicklookissue", populated, "2", nil),
            ("security", populated, "3", nil),
            ("filtered", filtered, nil, "2"),
            ("empty", empty, nil, nil),
            ("firstrun", makeStore(.signedOut), nil, nil),
        ]
        for (name, store, quickLookID, hoveredID) in scenarios {
            let panel = PanelController(store: store, updater: updater)
            panel.selection = ["2"]
            if let quickLookID {
                panel.showDetails(quickLookID)
                store.loadThreadDetails(for: quickLookID)
                for _ in 0..<100 {
                    guard let item = store.inbox.first(where: { $0.id == quickLookID }), store.threadDetails(for: item) == .loading else { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
            }
            panel.hoveredID = hoveredID
            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                let window = PanelController.makePanelWindow(
                    content: InboxPanel().environment(store).environment(panel).environment(updater).defaultAppStorage(defaults)
                )
                window.hidesOnDeactivate = false
                window.styleMask = [.borderless, .fullSizeContentView]
                window.isOpaque = true
                window.backgroundColor = .windowBackgroundColor
                window.appearance = NSAppearance(named: appearance)
                SnapshotCapture.hideOffScreen(window)
                window.orderFrontRegardless()
                await SnapshotCapture.write(window, to: directory.appending(path: "inbox-\(name)-\(suffix).png"))
                window.orderOut(nil)
            }
        }
        for style in MenuBarStyle.allCases {
            let label = menuBarImage(store: populated, style: style)
            guard let tiff = label.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: directory.appending(path: "menubar-\(style.rawValue).png"))
        }
        exit(0)
    }

    private static func load(_ store: InboxStore) async {
        await store.refresh()
        for _ in 0..<100 where store.inbox.contains(where: { $0.status == .loading }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

private struct FixtureTokenStorage: TokenStorage {
    let token: String?

    func read() -> String? { token }
    func save(_ token: String) throws {}
    func delete() throws {}
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        let isEmpty = request.value(forHTTPHeaderField: "Authorization") == "Bearer empty"
        let isGraphQL = url.path() == "/graphql"
        let isRead = request.httpMethod == "GET" || isGraphQL
        let body = isGraphQL
            ? FixtureData.graphQL(number: Self.graphQLNumber(in: request))
            : isEmpty && url.path() == "/notifications" ? Data("[]".utf8) : FixtureData.routes[url.path()]
        let status = isRead ? (body == nil ? 404 : 200) : 205
        let headers = ["X-OAuth-Scopes": "notifications, repo", "Content-Type": "application/json"]
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func graphQLNumber(in request: URLRequest) -> Int? {
        guard let stream = request.httpBodyStream else {
            let json = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            return (json?["variables"] as? [String: Any])?["number"] as? Int
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["variables"] as? [String: Any])?["number"] as? Int
    }
}

private enum FixtureData {
    struct Entry {
        let id: String
        let repository: String
        let kind: String
        let title: String
        let number: Int?
        let reason: String
        let unread: Bool
        let minutesAgo: Double
        let subject: [String: Any]?
        let comment: [String: Any]?
    }

    static let pullComment = """
    Thanks for picking this up! A few notes before I approve:

    - The header now uses the **system glass** instead of a custom material.
    - Rows keep the `8 pt` unread dot in the leading gutter.
    - Quick Look steps through threads with ↑ and ↓.

    ```swift
    .glassEffect(.regular, in: .capsule)
    ```

    One question: should *Done* ask for confirmation? See [the flow spec](https://github.com/tinecli/tidy/blob/main/docs/FLOW.md).
    """

    nonisolated(unsafe) static let entries: [Entry] = [
        Entry(id: "1", repository: "tinecli/tidy", kind: "PullRequest", title: "Adopt Liquid Glass in the inbox panel", number: 42, reason: "review_requested", unread: true, minutesAgo: 4,
              subject: ["state": "open", "draft": false, "merged": false, "user": ["login": "mira"], "body": "Moves the panel onto the system glass.", "html_url": "https://github.com/tinecli/tidy/pull/42"],
              comment: ["user": ["login": "jonas"], "body": pullComment, "html_url": "https://github.com/tinecli/tidy/pull/42#issuecomment-1"]),
        Entry(id: "2", repository: "tinecli/tidy", kind: "Issue", title: "Crash when the token is revoked while a poll is in flight", number: 57, reason: "mention", unread: true, minutesAgo: 18,
              subject: ["state": "open", "user": ["login": "sam"], "body": "Steps to reproduce:\n\n1. Connect a token\n2. Revoke it on github.com\n3. Wait for the next poll", "html_url": "https://github.com/tinecli/tidy/issues/57"],
              comment: nil),
        Entry(id: "3", repository: "acme/api", kind: "RepositoryDependabotAlertsThread", title: "Your repository has dependencies with security vulnerabilities", number: nil, reason: "security_alert", unread: true, minutesAgo: 52,
              subject: nil, comment: nil),
        Entry(id: "4", repository: "acme/api", kind: "CheckSuite", title: "CI workflow run failed for main branch", number: nil, reason: "ci_activity", unread: true, minutesAgo: 95,
              subject: nil, comment: nil),
        Entry(id: "5", repository: "acme/web", kind: "PullRequest", title: "Draft: Keyboard stepping between threads in Quick Look", number: 318, reason: "author", unread: false, minutesAgo: 160,
              subject: ["state": "open", "draft": true, "user": ["login": "gustaf"], "body": "Work in progress.", "html_url": "https://github.com/acme/web/pull/318"],
              comment: nil),
        Entry(id: "6", repository: "tinecli/tidy", kind: "PullRequest", title: "Paginate notifications up to 200 threads", number: 39, reason: "comment", unread: false, minutesAgo: 300,
              subject: ["state": "closed", "merged": true, "user": ["login": "mira"], "body": "Follows the Link header.", "html_url": "https://github.com/tinecli/tidy/pull/39"],
              comment: nil),
        Entry(id: "7", repository: "acme/web", kind: "Release", title: "v2.4.0", number: 9, reason: "subscribed", unread: false, minutesAgo: 1_500,
              subject: ["author": ["login": "release-bot"], "body": "## What's new\n\n- Faster builds", "html_url": "https://github.com/acme/web/releases/tag/v2.4.0"],
              comment: nil),
        Entry(id: "8", repository: "acme/api", kind: "Issue", title: "Support fine-grained tokens for notifications", number: 211, reason: "subscribed", unread: false, minutesAgo: 3_100,
              subject: ["state": "closed", "state_reason": "not_planned", "user": ["login": "pat"], "body": "GitHub doesn't expose notifications to fine-grained tokens.", "html_url": "https://github.com/acme/api/issues/211"],
              comment: nil),
        Entry(id: "9", repository: "acme/web", kind: "PullRequest", title: "Remove the legacy settings window", number: 301, reason: "review_requested", unread: true, minutesAgo: 4_400,
              subject: ["state": "closed", "merged": false, "user": ["login": "sam"], "body": "Superseded.", "html_url": "https://github.com/acme/web/pull/301"],
              comment: nil),
        Entry(id: "10", repository: "tinecli/tidy", kind: "Issue", title: "Remember the Unread and All choice between launches", number: 33, reason: "author", unread: false, minutesAgo: 6_000,
              subject: ["state": "closed", "user": ["login": "gustaf"], "body": "Fixed.", "html_url": "https://github.com/tinecli/tidy/issues/33"],
              comment: nil),
    ]

    nonisolated(unsafe) static let alerts: [[String: Any]] = [
        ["number": 14, "state": "open", "html_url": "https://github.com/acme/api/security/dependabot/14",
         "dependency": ["package": ["name": "undici"]],
         "security_advisory": ["ghsa_id": "GHSA-3787-6prv-h9w3", "summary": "Proxy-Authorization header not cleared on cross-origin redirect", "severity": "critical"]],
        ["number": 12, "state": "open", "html_url": "https://github.com/acme/api/security/dependabot/12",
         "dependency": ["package": ["name": "path-to-regexp"]],
         "security_advisory": ["ghsa_id": "GHSA-9wv6-86v2-598j", "summary": "Backtracking regular expressions cause ReDoS", "severity": "high"]],
        ["number": 9, "state": "open", "html_url": "https://github.com/acme/api/security/dependabot/9",
         "dependency": ["package": ["name": "cookie"]],
         "security_advisory": ["ghsa_id": "GHSA-pxg6-pf52-xh8x", "summary": "Accepts cookie name, path and domain with out of bounds characters", "severity": "low"]],
    ]

    static let pullDescription = """
    ## Summary

    Moves the inbox panel onto the system **Liquid Glass** material and drops the custom blur.

    - Header and footer sit directly on the glass
    - Rows keep their hover and selection treatment
    - Quick Look inherits the same background

    ## Testing

    1. Open the panel in light and dark mode
    2. Toggle Reduce Transparency in Accessibility settings
    3. Step through threads with ↑ and ↓ in Quick Look

    ## Notes

    The snapshot hook still captures the panel off-screen, so the PNGs in `dist/snapshots` reflect the change.
    """

    static func graphQL(number: Int?) -> Data? {
        let minutes = { (ago: Double) in Date.now.addingTimeInterval(-ago * 60).formatted(.iso8601) }
        let who = { (login: String) -> [String: Any] in ["login": login] }
        let comment = { (id: String, login: String, body: String, ago: Double, state: String?) -> [String: Any] in
            ["id": id, "author": who(login), "body": body, "createdAt": minutes(ago), "url": "https://github.com/tinecli/tidy/pull/42#\(id)", "state": state ?? NSNull()]
        }
        let node: [String: Any]
        if number == 42 {
            node = [
                "kind": "PullRequest", "author": who("mira"), "createdAt": minutes(2_900), "url": "https://github.com/tinecli/tidy/pull/42",
                "body": pullDescription,
                "labels": ["nodes": [["name": "design", "color": "d4c5f9"], ["name": "macOS 26", "color": "0e8a16"], ["name": "enhancement", "color": "a2eeef"]]],
                "assignees": ["nodes": [who("mira")]],
                "milestone": ["title": "0.3"],
                "baseRefName": "main", "headRefName": "mira/liquid-glass",
                "additions": 248, "deletions": 96, "changedFiles": 9, "mergeable": "MERGEABLE", "reviewDecision": "REVIEW_REQUIRED",
                "latestReviews": ["nodes": [["state": "APPROVED", "author": who("sam")], ["state": "COMMENTED", "author": who("jonas")]]],
                "reviewRequests": ["nodes": [["requestedReviewer": who("gustaf")], ["requestedReviewer": ["slug": "design"]]]],
                "commits": ["nodes": [["commit": ["statusCheckRollup": ["state": "FAILURE", "contexts": ["nodes": [
                    ["name": "build", "status": "COMPLETED", "conclusion": "SUCCESS"],
                    ["name": "test", "status": "COMPLETED", "conclusion": "SUCCESS"],
                    ["name": "swift-format", "status": "COMPLETED", "conclusion": "SUCCESS"],
                    ["name": "lint", "status": "COMPLETED", "conclusion": "FAILURE"],
                    ["name": "ui-tests", "status": "IN_PROGRESS"],
                ]]]]]]],
                "timelineItems": ["totalCount": 7, "nodes": [
                    comment("issuecomment-11", "mira", "Ready for another look. Screenshots are in the description.", 240, nil),
                    comment("pullrequestreview-12", "sam", "", 180, "APPROVED"),
                    comment("pullrequestreview-13", "jonas", pullComment, 30, "COMMENTED"),
                    comment("issuecomment-14", "mira", "Good catch, no confirmation: Done can be undone for 5 seconds. Fixed the lint failure in `3f2a1c0`.", 4, nil),
                ]],
            ]
        } else if number == 57 {
            node = [
                "kind": "Issue", "author": who("sam"), "createdAt": minutes(400), "url": "https://github.com/tinecli/tidy/issues/57",
                "body": "Steps to reproduce:\n\n1. Connect a token\n2. Revoke it on github.com\n3. Wait for the next poll",
                "labels": ["nodes": [["name": "bug", "color": "d73a4a"], ["name": "crash", "color": "b60205"]]],
                "assignees": ["nodes": [who("gustaf")]],
                "milestone": ["title": "0.3"],
                "comments": ["totalCount": 2, "nodes": [
                    comment("issuecomment-21", "jonas", "Reproduced on main. The poll task keeps the old client alive.", 60, nil),
                    comment("issuecomment-22", "sam", "@gustaf can you take a look?", 18, nil),
                ]],
            ]
        } else {
            return nil
        }
        return try? JSONSerialization.data(withJSONObject: ["data": ["repository": ["issueOrPullRequest": node]]])
    }

    static let routes: [String: Data] = {
        let api = "https://api.github.com"
        let now = Date.now
        var routes: [String: Data] = [:]
        let threads: [[String: Any]] = entries.map { entry in
            let segment = ["PullRequest": "pulls", "Issue": "issues", "Release": "releases"][entry.kind]
            let subjectPath = segment.flatMap { segment in entry.number.map { "/repos/\(entry.repository)/\(segment)/\($0)" } }
            let commentPath = entry.comment.map { _ in "/repos/\(entry.repository)/issues/comments/\(entry.id)00" }
            if let subjectPath, let subject = entry.subject { routes[subjectPath] = try? JSONSerialization.data(withJSONObject: subject) }
            if let commentPath, let comment = entry.comment { routes[commentPath] = try? JSONSerialization.data(withJSONObject: comment) }
            let owner = String(entry.repository.prefix { $0 != "/" })
            return [
                "id": entry.id,
                "reason": entry.reason,
                "unread": entry.unread,
                "updated_at": now.addingTimeInterval(-entry.minutesAgo * 60).formatted(.iso8601),
                "subject": [
                    "title": entry.title,
                    "type": entry.kind,
                    "url": subjectPath.map { api + $0 } ?? NSNull(),
                    "latest_comment_url": (commentPath ?? subjectPath).map { api + $0 } ?? NSNull(),
                ],
                "repository": [
                    "full_name": entry.repository,
                    "private": false,
                    "html_url": "https://github.com/\(entry.repository)",
                    "owner": ["login": owner],
                ],
            ]
        }
        routes["/notifications"] = try? JSONSerialization.data(withJSONObject: threads)
        routes["/repos/acme/api/dependabot/alerts"] = try? JSONSerialization.data(withJSONObject: alerts)
        return routes
    }()
}
#endif
