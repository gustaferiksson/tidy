# TidyCore API

The contract between TidyCore and the SwiftUI app. TidyCore imports Foundation,
Network, Security and CryptoKit only; no SwiftUI or AppKit. Everything listed
here is `public`. All value types are `Sendable`, and `Codable` unless noted.

## InboxStore (`@MainActor @Observable final class`)

One instance for the app's lifetime. Views read it; actions go through its methods.

```swift
InboxStore(
  directory: URL = InboxStore.defaultDirectory,        // ~/Library/Application Support/dev.gustaf.tidy
  tokenStorage: any TokenStorage = KeychainTokenStore(),
  session: URLSession = GitHubClient.makeSession(),
  baseURL: URL = GitHubClient.defaultBaseURL,
  commitDelay: Duration = .seconds(5),                 // undo window
  bannerWait: Duration = .seconds(5),                  // max wait for subject data before a banner
  networkPaths: AsyncStream<Bool>? = nil,              // nil = NWPathMonitor
  now: @Sendable () -> Date = { .now }
)
```

### Lifecycle

| Call | When |
|---|---|
| `start()` | Once at launch. Starts network monitoring, polling (if signed in) and commits changes queued on disk |
| `stop()` | Stops polling |
| `pause()` / `resume()` | Wire to `NSWorkspace` `willSleep` / `didWake`. `resume()` polls at once |
| `pollNow()` | Refresh button and ⌘R |
| `refresh() async -> Duration?` | One poll; returns the next delay, nil when polling stopped (401, missing scope). Mostly for tests |
| `connect(token:) async throws` | Settings › GitHub › Connect. Throws `GitHubError` (`.fineGrainedToken` before any request, `.missingScopes`, `.unauthorized`, `.offline`…), show `error.message` inline. On success saves to Keychain, resets the banner baseline and starts polling |
| `disconnect()` | Deletes the token and all account data (inbox, queue, muted, cache) |
| `flushPending() async` | Call when the panel closes: sends queued changes now |

Network loss pauses polling and sets `issue = .offline`; reconnect resumes polling and sends queued changes.

### Observable state

| Property | Meaning |
|---|---|
| `inbox: [InboxItem]` | Every thread not archived, newest `updatedAt` first, filters not applied |
| `visibleItems: [InboxItem]` | `inbox` after `scope` and hide rules (hidden rows included while `showsHidden`). The Unread/All segment is the app's own `filter(\.isUnread)` |
| `unreadCount: Int` | Menu bar count: unread, not hidden by a rule. Ignores `scope`. Rows whose author/state rule is still waiting for subject data count (they are visible too), so the count can drop once the data arrives |
| `hiddenCount: Int` | Footer "N hidden by filters" |
| `showsHidden: Bool` (settable) | Footer "Show" |
| `scope: InboxScope` (settable) | Header filter: `participatingOnly`, `repository`; `isActive` for the capsule |
| `repositories: [String]` | Repos seen, sorted, for the Repository submenu and rule picker |
| `isSignedIn`, `account: GitHubAccount?` | `account.user.login/avatarURL`, `account.scopes` (rechecked every poll). A missing or unreadable `account.json` is refilled via `GET /user` on the next successful poll |
| `hasLoaded` | false until the first successful fetch (first-load spinner) |
| `isRefreshing` | Spinner on the refresh button |
| `isCapped` | 200-thread cap hit: footer "Showing the last 14 days" |
| `lastSync: Date?` | "Updated 1m ago" |
| `issue: SyncIssue?` | `.offline`, `.rateLimited(resumesAt:)`, `.ssoRequired(organization:url:)`, `.notResponding` (third failed poll in a row), `.unauthorized`, `.missingScope`, `.keychainUnavailable` (the token couldn't be read; `isSignedIn` stays true and every poll retries the read) |
| `isOnline: Bool` | Current network path |
| `pending: [PendingChange]`, `undoableChange: PendingChange?` | Undo toast: `undoableChange.message` ("Marked 3 as done"); nil means hide the toast. Only the latest action is undoable, and only for `commitDelay` after it (or until it is sent). Changes still queued offline or restored from `pending.json` are never undoable |
| `failure: ActionFailure?` | Footer "Couldn't update 2 notifications · Retry" (`message`, `count`) |
| `muted: [MutedThread]` | Muted threads listed in Settings › Filters |
| `rules: [FilterRule]` (settable) | Filter rules in order, persisted on set |
| `silencedReasons: Set<Reason>` (settable) | "Notify for" unchecked reasons, persisted on set. Empty = notify for all |

### Actions

All are synchronous and optimistic: state changes at once, the GitHub call goes out after `commitDelay`. Queued actions yield `.withdraw(threadIDs:)` on `events`.

| Method | Local effect | GitHub call |
|---|---|---|
| `markRead(_ ids: [String])` | Rows turn read | `PATCH` per unread thread |
| `markRead(opening id: String)` | Quick Look was opened (not peeked): the row turns read. Sent at once, never undoable, leaves `undoableChange` alone | `PATCH` if unread, else none |
| `markDone(_ ids: [String])` | Rows leave `inbox` (archive). Undo puts them back | `DELETE` per thread, 4 at a time |
| `markAllRead()` | Rows turn read (never rows hidden by a rule, even while `showsHidden`). After a `PUT`, rows stay read locally until a poll shows them read or with newer activity, since GitHub may answer 202 and apply it later | `PUT /notifications` (no scope, nothing hidden), `PUT /repos/{o}/{r}/notifications` (repo scope), or `PATCH` per visible unread thread (Participating Only or hide rules hiding something) |
| `muteThread(_ id: String)` | Row leaves `inbox`, like Done | `PUT …/subscription {ignored: true}` then `DELETE`; adds to `muted` on success |
| `muteRepository(_ fullName: String)` | Appends rule "Repository is X → Hide", unless one already hides exactly that repository | none |
| `unmute(_ id: String) async throws` | Removes from `muted` | `PUT …/subscription {ignored: false}`, immediate |
| `undo() -> [String]` | Reverts `undoableChange`; returns its thread ids to scroll to and select. `[]` once the window has passed | cancelled |
| `retryFailed()` | Re-applies failed changes and sends them now | as above |
| `dismissFailure()` | Clears `failure` | none |
| `loadDetails(for id: String)` | Quick Look Retry: refetches subject data | `GET subject.url` etc. |
| `loadThreadDetails(for id: String)` | Quick Look opened or stepped to a thread: fetches its rich details unless already loaded or loading for the same `updatedAt` (a `.failed` entry refetches, so it is also Retry). No-op for kinds `ThreadDetails.isSupported` rejects. Never called by polling | One `POST /graphql` |

### Thread details (Quick Look only)

`threadDetails(for item: InboxItem) -> ThreadDetailsStatus?` reads the in-memory cache, keyed by thread id and `updatedAt`: nil means not fetched for this `updatedAt` yet. Statuses: `.loading` (show the skeleton), `.loaded(ThreadDetails)`, `.unavailable` (not found, or the token lacks the scope GraphQL wants, e.g. discussions without `read:discussion`: show the basic preview, no error), `.failed` (offer Retry). The cache is cleared on disconnect and pruned to threads still in the inbox on each load. Nothing is written to disk.

`ThreadDetails`: `author`, `createdAt`, `url`, `body` (Markdown), `labels: [IssueLabel]` (`name`, `color` hex without `#`), `assignees`, `milestone?`, `comments: [TimelineComment]` (oldest first, at most 10), `totalComments` (all comments and reviews; show "View all N on GitHub" when larger than `comments.count`), `pullRequest: PullRequestDetails?`, `discussion: DiscussionDetails?`. `ThreadDetails.isSupported(thread)`: pull requests and issues with a number, and discussions.

- `PullRequestDetails`: `baseBranch`, `headBranch`, `additions`, `deletions`, `changedFiles`, `reviewDecision: ReviewDecision?` (`.approved .changesRequested .reviewRequired`, `title`), `reviewers: [Reviewer]` (`user`, `state: ReviewState`), `checks: CheckSummary?`, `hasConflicts`.
- `ReviewState`: `.approved .changesRequested .commented .dismissed .requested`, `title`. A reviewer who is requested again shows as `.requested`, not their older review.
- `CheckSummary`: `state: CheckState` (`.success .failure .pending`), `passed`, `failing: [String]`, `pending: [String]` (check names); `summary` is the one-line text ("3 checks passed · 1 failing: lint · 1 pending"). Skipped and neutral checks count as neither.
- `TimelineComment`: `id`, `author?`, `body`, `createdAt`, `url?`, `review: ReviewState?` (set for pull request reviews; a review with an empty body is an event row, and empty "commented" reviews are dropped), `isAnswer` (discussions).
- `DiscussionDetails`: `category?`, `isAnswered`.

Pull requests and issues use one query (`repository.issueOrPullRequest(number:)`). Discussion notifications have no `subject.url`, so their query is a separate document that searches the repository by exact title (`search(type: DISCUSSION)`); a scope error there can't affect pull request or issue details. GraphQL errors in a 200 response map to `GitHubError`: `NOT_FOUND`/`INSUFFICIENT_SCOPES` → `.notFound`, `FORBIDDEN` → `.forbidden`, `RATE_LIMITED` → `.rateLimited`, anything else without data → `.decoding`.

`markRead`, `markRead(opening:)` and `markDone` also accept ids not loaded yet (banner actions right after relaunch): they apply, not undoable, on the next fetch that returns a list (a 304 keeps them waiting). Ids that fetch doesn't list are dropped. Kept in memory only.

After a Done or Mute is sent, polls that still list the thread with the same `updatedAt` don't bring it back (GitHub can lag). A newer `updatedAt` brings it back as unread. Kept in memory only.

On failure the affected rows roll back and `failure` is set. Offline failures stay queued instead. The queue is persisted (`pending.json`) and resent on next `start()`.

### Banner events

`events: AsyncStream<InboxEvent>`, single consumer.

- `.newThread(InboxItem)`: post a banner. Title `item.title`, subtitle `"\(repo) · \(item.thread.reason.title)"`, body first line of `item.previewMarkdown`, `threadIdentifier` = repo full name.
- `.summary(count:)`: more than 5 new at once; post "N new notifications" instead.
- `.withdraw(threadIDs:)`: remove delivered banners for these threads. Sent for local actions and for threads a poll shows were read elsewhere (github.com).

The store already applies: baseline-only first fetch after launch or token change, unread only, `silencedReasons`, and any matching rule (Hide, Don't Notify, opt-in actions). It waits up to `bannerWait` for subject data first. The app still drops banners while the panel is open.

## InboxItem

`thread: NotificationThread`, `status: DetailsStatus` (`.loading`, `.loaded(SubjectDetails)`, `.failed`). Derived:

| Property | Use |
|---|---|
| `id`, `isUnread` | |
| `title` | Row title. Dependabot rows are retitled ("3 vulnerable dependencies · 2 critical") once loaded |
| `glyph: StateGlyph` | Row glyph; grey base Octicon while loading or failed |
| `state: SubjectState?`, `severity: Severity?` | Quick Look state word (`state.title`), security severity word (`severity.title`) |
| `webURL: URL` | Open on GitHub / Copy Link (anchored to the latest comment when known) |
| `author: GitHubUser?`, `details?.latestComment?.author` | Quick Look people |
| `previewMarkdown: String?` | Latest comment body, else subject body (Markdown source) |
| `details?.alerts: [SecurityAlert]` | Quick Look alert list: `package`, `severity`, `summary`, `advisoryID`, `htmlURL` |
| `thread.number` | `#123` for PRs, issues, discussions |

## Models

- `NotificationThread`: `id`, `reason: Reason`, `unread`, `updatedAt`, `lastReadAt?`, `subject: Subject`, `repository: Repository`, `number?`, `ciState?`.
- `Subject`: `title`, `kind: SubjectKind`, `url?`, `latestCommentURL?`.
- `Repository`: `fullName`, `owner: GitHubUser`, `isPrivate`, `htmlURL`.
- `GitHubUser`: `login`, `avatarURL?`. `GitHubAccount`: `user`, `scopes`.
- `SubjectKind`: `.pullRequest .issue .discussion .release .commit .checkSuite .workflowRun .dependabotAlerts .secretScanningAlert .repositoryAdvisory .securityAdvisoryCredit .repositoryInvitation .unknown(String)`; `title` ("Pull request"), `category: SubjectCategory`, `isSecurity`. Unknown API types decode to `.unknown`.
- `SubjectCategory` (filter "Type is"): `.pullRequest .issue .securityAlert .release .discussion .ci .commit .other`, `title`.
- `Reason`: string-backed struct, unknown values survive. Constants (`.reviewRequested`, `.mention`, …), `Reason.allKnown`, `title` ("Review requested"), `group: ReasonGroup`.
- `ReasonGroup`: `.participating .security .activity`, `title`, `reasons` (the "Notify for" checklist).
- `SubjectState`: `.open .draft .merged .closed .notPlanned .answered .failed .succeeded .cancelled`, `title`; `SubjectState.filterable` for the rule editor. Issues closed as completed are `.closed`.
- `Severity`: `.low .moderate .high .critical` (Comparable), `title`.

## StateGlyph

`StateGlyph(kind:state:severity:)` gives `octicon: Octicon`, `tone: StateTone` and `label` (VoiceOver and tooltip, "Pull request, draft"). `StateGlyph.baseOcticon(for:)` for "State unavailable". Kind-to-Octicon mapping is the FLOW §5 table; Dependabot alerts use `.alert` (warning triangle) tinted by highest severity.

`Octicon`: one case per GitHub Octicon the glyphs and the Quick Look review and check badges use. `rawValue` is the Octicon name and the custom symbol's asset name in the app's `Resources/Assets.xcassets/Octicons`, so render it with `Image(octicon.rawValue)` and size it with `.font` like an SF Symbol.

`StateTone`: `.green .purple .red .grey .orange .yellow`. The app maps tones to colours (FLOW §5):

| Tone | Light | Dark | Increase Contrast |
|---|---|---|---|
| green | #1a7f37 | #3fb950 | `.green` |
| purple | #8250df | #a371f7 | `.purple` |
| red | #d1242f | #f85149 | `.red` |
| grey | #59636e | #9198a1 | `.gray` |
| orange | #bc4c00 | #db6d28 | `.orange` |
| yellow | #9a6700 | #d29922 | `.yellow` |

## Filters

- `FilterRule(id:conditions:action:savedAt:)`: all conditions must match. `needsSubject`.
- `FilterCondition`: `.repository(String)`, `.notRepository(String)` (a value without `/` matches the owner), `.reason(Reason)`, `.category(SubjectCategory)`, `.author(String)`, `.state(SubjectState)`; `needsSubject`; `FilterCondition.authorPresets`.
- `RuleAction`: `.hide .dontNotify .hideAndMarkRead .hideAndMarkDone`; `title`, `hides`, `isOptIn` (show the warning). Opt-in actions only call GitHub for threads updated after `savedAt`.
- `rules.outcome(for: item) -> FilterOutcome`: `.none`, `.undetermined` (an author/state rule is waiting for subject data; treated as not matching), `.matched(FilterRule)`; `hides`, `silences`.

## GitHubClient and helpers

`GitHubClient(token:session:baseURL:cache:)` is a `Sendable` struct the store uses internally. Public for Settings and tests: `validate()`, `notifications(since:ifModifiedSince:)`, `details(for:previous:)`, `threadDetails(for:)`, `markRead`, `remove`, `markAllRead(lastReadAt:repository:)`, `mute`, `unmute`, `get(_:from:)`, `GitHubClient.since(now:)`.

- The token is only sent to `baseURL`'s scheme and host: any other URL (subject, comment, `Link` next page) fails with `.forbidden`, and a foreign next page ends paging.
- `GitHubError`: `.fineGrainedToken .unauthorized .missingScopes([String]) .ssoRequired(organization:url:) .rateLimited(resetsAt:) .offline .forbidden .notFound .server(status:) .unexpectedStatus(Int) .decoding`; `message` is the inline text for Settings.
- `WebLink.url(for:details:)`, `WebLink.fallback(for:repository:)`, `WebLink.webURL(forAPI:)`.
- `TokenStorage` protocol: `read() throws -> String?` (nil = no token, throw = Keychain error), `save`, `delete`. A non-throwing `read()` still conforms. `KeychainTokenStore(service: "dev.gustaf.tidy", account: "github-token")`: generic password, this device only, in the data protection keychain. Builds without an application identifier (ad-hoc, `swift test`) get `errSecMissingEntitlement` there and fall back to the legacy keychain; reads also fall back so a legacy item is still found. Saves update in place, never delete-then-add. Set `TIDY_KEYCHAIN_TESTS=1` to run the real Keychain round-trip test (throwaway service name).
- `InboxStore.networkAvailability() -> AsyncStream<Bool>` wraps `NWPathMonitor`.

## Files in the support directory

`rules.json`, `silenced-reasons.json`, `pending.json`, `muted.json`, `account.json`, and `Cache/` (ETag responses). The token is only in the Keychain. A `done.json` left by older versions (the local Done section) is deleted at launch without calling GitHub; those threads stay read on github.com. A `pending.json` that still holds an old Remove All fails to decode and is set aside as `.corrupt`. A file that fails to decode is renamed to `NAME.corrupt` (replacing an older one) and the store starts from empty for it.
