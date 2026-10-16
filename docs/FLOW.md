# Tidy: UX flow spec

Tidy runs on macOS 26 only. It lives in the menu bar as a `MenuBarExtra` with the `.window` style and works as a GitHub notifications inbox.

- Pure SwiftUI, with no Dock icon (`LSUIElement`).
- The panel sits on Liquid Glass (`.glassEffect`) with a clear window background, and adds no other backgrounds.
- Every size is a multiple of 4 pt.

## 1. Surfaces

| Surface | What it is |
|---|---|
| Menu bar label | A glyph, an unread count, or both |
| Panel | 400 × 560 pt, fixed size. Shows the Inbox list, or Quick Look pushed on top of it |
| macOS banners | Sent through `UNUserNotificationCenter` |
| Settings scene | Tabs: General, GitHub, Notifications, Filters, About |

Reopening the app from Finder or Spotlight (`applicationShouldHandleReopen`) opens the panel. That way people can still reach the inbox when the system hides the menu bar extra.

## 2. Menu bar label

Set in Settings › General › Menu Bar.

| Style | Unread > 0 | Unread = 0 |
|---|---|---|
| Icon + Unread Count (default) | `tray.badge` 3 | `tray` |
| Count Only | 3 | `tray` (so the item is never empty) |
| Icon Only | `tray.badge` | `tray` |

- The count tops out at "99+".
- It counts threads that are unread and not hidden by a filter.
- Glyphs are template images.
- When the token is missing or invalid, the label shows `tray` with no count.
- When offline or rate limited, the label keeps the last known count.

## 3. Panel: Inbox

**Header (44 pt):**
- **Leading:** a segmented control with Unread and All.
- **Trailing:** three buttons.
  - `line.3.horizontal.decrease.circle` opens a menu with Participating Only and a Repository submenu. The submenu is built locally from the repos in the list.
  - `arrow.clockwise.circle` refreshes. It turns into a spinner while a fetch runs.
  - `ellipsis.circle` opens a menu with Mark All as Read, Settings… (⌘,) and Quit Tidy (⌘Q).
- While a filter is active, it shows as a removable capsule under the header.

**List:**
- One flat list, newest `updated_at` first.
- Each row names its repo. The list isn't grouped by repo, because Mail and Notification Center triage by recency, and section headers cost too much height in a 560 pt panel. The repo filter covers narrowing down to one repo.

**Row (at least 52 pt, padding 4 pt trailing and 8 pt vertical):**
- The age and the hover buttons sit near the trailing edge, aligned with the header's trailing button and the footer. The scroller always overlays, so it never reserves a gutter.
- A 12 pt leading gutter holds an 8 pt accent-colour dot when the thread is unread. **No coloured left bars.**
- A 20 pt column holds the 16 pt state glyph (§5).
- The title uses `.body`, wraps to at most 2 lines, and truncates in the middle.
- The meta line uses `.subheadline` in secondary colour, for example `owner/repo #123 · Review requested · 4m`.
- Security rows add the severity word to the meta line, for example `· Critical`.
- While a row's subject is still loading, it shows the base glyph in grey and its meta line is redacted.

| | Title | Dot | Glyph |
|---|---|---|---|
| Unread | semibold, primary colour | yes | full colour |
| Read | regular weight, primary colour | no (the gutter keeps its width so titles stay aligned) | full colour |

As in Mail, weight and the dot are the only difference: read rows aren't greyed out, and the meta line is secondary in both.

There is no Done section. Done archives a thread (§4), so it leaves the list.

**Unread segment:** a thread opened in Quick Look (§7) stays in the Unread list, read, until the panel closes, so stepping back with ↑ still finds it.

**Footer (28 pt, secondary colour):** shows one of these:
- `Updated 1m ago`, or a status from §8.
- `Marked as done · Undo` while a change can be undone (see §4). Only a failure outranks it.
- `4 hidden by filters · Show`. This link is the only way to reveal hidden items.
- `Showing the last 14 days` once the 200-thread cap is reached.

## 4. Read and Done model

Tidy works like an email inbox. Opening a thread reads it, and Done archives it.

| Action | How | What changes locally | GitHub call |
|---|---|---|---|
| Open | Click, ↩, context menu Quick Look, banner Quick Look, ↑ ↓ in Quick Look | Quick Look opens and the row turns read. No undo | `PATCH /notifications/threads/{id}`, sent at once |
| Peek | Space | Quick Look opens. The thread stays unread | none |
| Mark as Read | ⇧I, swipe, context menu | The row turns read | `PATCH /notifications/threads/{id}` |
| Done | E, hover, swipe, context menu, Quick Look, banner | The row leaves the list | `DELETE /notifications/threads/{id}` (GitHub's "mark as done"), 4 at a time |
| Mark All as Read | ⇧⌘I, the ⋯ menu | Every row turns read | See below |

**Done is archive.** Nothing is kept locally: the thread disappears from github.com's inbox too. When it gets new activity, GitHub lists it again and it comes back as unread.

**Mark All as Read:**
- With no filter, Tidy calls `PUT /notifications` with `last_read_at` set to the newest `updated_at` it has seen.
- With a repo filter, it calls `PUT /repos/{o}/{r}/notifications` instead.
- When GitHub answers 202 (it handles the request in the background), the rows stay read and the next poll reconciles them.
- When Participating Only or hide rules are active, Tidy sends a `PATCH` for each visible thread instead, so hidden threads aren't touched.

**Selection:** `List(selection:)` supports ⌘-click, ⇧-click and ⌘A, and actions apply to the whole selection. To mark everything Done, press ⌘A, then E.

**Resurfacing:**
- A Done thread stays out of the list while polls still return it with the same `updated_at` (GitHub can lag). Once its `updated_at` moves on, it returns to the top as unread.
- If a thread disappears from an `all=true` response, someone marked it done on github.com, so Tidy removes it locally.

**Optimistic updates and undo:**
- The UI changes at once. The GitHub call is sent 5 s later.
- During that window, the footer reads "Marked as done · Undo" ("Marked 3 as done" for a batch) in place of "Updated…", as in Mail. There's no floating toast, so repeated actions just update the text. ⌘Z also undoes.
- Undo cancels the pending call, puts the rows back, scrolls to them and selects them.
- The window is 5 s because GitHub has no "mark unread" or "undo done" call, so neither can be reversed once it's sent.
- Opening a thread is the exception: its read is sent at once and has no undo, as in Mail. It never replaces a Done that's still undoable.
- Closing the panel sends whatever is pending right away. The queue is saved to disk.
- On failure, the change rolls back and the footer reads "Couldn't update 2 notifications · Retry".
- While offline, changes stay queued until the connection returns.
- Done has no confirmation alert: it can be undone, and GitHub brings a thread back on new activity anyway.

## 5. State glyphs

State glyphs are GitHub's own [Octicons](https://github.com/primer/octicons) (MIT, notice in `LICENSES/octicons.txt`), shipped as custom symbols in `Resources/Assets.xcassets/Octicons`. Each one is the 16 px Octicon converted to an SF Symbols template by `icon/octicon-symbols.py` (`python3 icon/octicon-symbols.py <octicons>/build/svg Resources/Assets.xcassets/Octicons`), scaled so a 16 px circle matches the SF `circle` and centred on the cap height. They tint and size like SF Symbols. UI chrome (buttons, menus, the menu bar label, empty states) stays on SF Symbols.

**Colours (GitHub light / dark):**

| Name | Light | Dark |
|---|---|---|
| Green | #1a7f37 | #3fb950 |
| Purple | #8250df | #a371f7 |
| Red | #d1242f | #f85149 |
| Grey | #59636e | #9198a1 |
| Orange (high) | #bc4c00 | #db6d28 |
| Yellow (moderate) | #9a6700 | #d29922 |

With Increase Contrast on, Tidy uses the system colours instead (`.green`, `.purple`, `.red`, `.orange`, `.yellow`, `.gray`).

| Subject and state | Octicon | Colour |
|---|---|---|
| PR open / draft / closed | `git-pull-request` / `git-pull-request-draft` / `git-pull-request-closed` | green / grey / red |
| PR merged | `git-merge` | purple |
| Issue open | `issue-opened` | green |
| Issue closed as completed | `issue-closed` | purple |
| Issue closed as not planned | `skip` | grey |
| Discussion / answered | `comment-discussion` / `discussion-closed` | green / purple |
| Release | `tag` | grey |
| Commit | `git-commit` | grey |
| CI failed / succeeded / cancelled | `x-circle` / `check-circle` / `stop` | red / green / grey |
| Dependabot (`RepositoryDependabotAlertsThread`, legacy `RepositoryVulnerabilityAlert`) | `alert` | Highest open severity: critical red, high orange, moderate yellow, low grey |
| `SecretScanningAlert` | `key` | red |
| `RepositoryAdvisory` | `shield` | severity colour |
| `SecurityAdvisoryCredit` | `shield-check` | purple |
| `RepositoryInvitation` | `person-add` | grey |
| Unknown type, or the state fetch failed | The type's base Octicon, otherwise `bell` | grey |

**Pull request states differ by shape as well as colour**, and state never relies on either alone:
- Every glyph has a VoiceOver label and a tooltip, for example "Pull request, draft".
- With Differentiate Without Color on, the meta line adds the state word.
- Quick Look always shows the state as text.

**CI state** comes from the thread title ("… workflow run failed for …"), because `subject.url` is null for CheckSuite.

**Dependabot threads:**
- They arrive with reason `security_alert`, `subject.url` = null, and a generic title.
- Tidy calls `GET /repos/{o}/{r}/dependabot/alerts?state=open`, which works with a classic token that has `repo`.
- It then retitles the row, for example "4 vulnerable dependencies · 1 critical".

**Secret scanning and advisories** (best effort):
- Secret scanning uses `…/secret-scanning/alerts?state=open`.
- Repository advisories use `…/security-advisories`.

**When a security call fails:** on a 403 or 404, the row falls back to a grey glyph with the GitHub link.

## 6. Data and caching

**Polling:**
- Tidy requests `GET /notifications?all=true&since=<local midnight 14 days ago>&per_page=50`.
- `since` is rounded to midnight so the URL stays stable and the cache keeps working.
- Page 1 sends `If-Modified-Since` with the last `Last-Modified` value. A 304 ends the poll and doesn't count against the rate limit.
- Pages 2–4 are fetched only after a 200, up to 200 threads in total.
- The interval is `max(60, X-Poll-Interval)` seconds.
- Polling pauses while the Mac sleeps or the network is unavailable (`NWPathMonitor`).
- Each poll rechecks `X-OAuth-Scopes`.

**Extra calls per thread.** Each runs only when the thread is new or its `updated_at` changed.

| Need | Call |
|---|---|
| State, draft, merged, author, body, `html_url` | `subject.url` |
| Latest comment and its author | `latest_comment_url`, only when the URL changed |
| Security details | The alert endpoints in §5 |

**Quick Look details** (§7) come from one GraphQL request (`POST /graphql`, the same classic token, host still `api.github.com`), sent only when Quick Look opens or steps to a pull request, issue or discussion. Polling never sends it, since it costs rate limit. The result is kept in memory per thread id and `updated_at`, so reopening a thread costs nothing until it has new activity. Discussions are looked up by exact title in a separate query; if the token can't read discussions, Quick Look shows the basic preview instead of an error. No extra token scope is asked for.

**Cache:**
- Responses are cached on disk in Application Support, keyed by URL, with their ETag.
- Requests send `If-None-Match`, so a 304 costs nothing.
- At most 4 requests run at once, and visible rows go first.

**Links when `subject.url` is null:**

| Type | Link |
|---|---|
| CheckSuite | `/{repo}/actions` |
| Dependabot | `/{repo}/security/dependabot` |
| Secret scanning | `/{repo}/security/secret-scanning` |
| Anything else | The repo page |

## 7. Quick Look

Quick Look is the only detail view. It's pushed inside the panel with `NavigationStack` at the same fixed size, the way Control Center modules drill in. An expanding row can't hold a long Markdown body.

**Opening and moving:**
- A click or ↩ opens the selected row and marks it read (⌘-click and ⇧-click only extend the selection).
- Space peeks: it opens the same view without marking read.
- Space, Esc, ⌘[ or `chevron.backward` closes it.
- ↑ and ↓ step through threads without leaving Quick Look. Each thread stepped to is marked read, even after a Space peek, since stepping is reading.
- Done and Mute Thread step to the next thread, which is then marked read too.

**Content:**
- The state glyph with the state word ("Merged").
- `Pull request #123 · owner/repo`.
- The title.
- Author, last commenter, reason, and the relative time (a tooltip shows the absolute time).
- Pull requests, issues and discussions then show their details (§6), below a divider:
  - **Status:** a two-column grid (72 pt labels in secondary colour). Pull requests: Branch (`base ← head` in monospaced, then `+248 −96 · 9 files`), Reviews (the review decision, then one capsule per reviewer: 16 pt avatar, login and a state Octicon: `check` green approved, `file-diff` red changes requested, `comment` grey commented, `dot-fill` yellow requested), Checks (one line, `check-circle` / `x-circle` / `dot-fill`: "3 checks passed · 1 failing: lint · 1 pending"), Merge ("Conflicts with main", only when conflicting). Every subject: Category (discussions), Labels (capsules in the label's GitHub colour: solid in light mode with black or white text, tinted with a border in dark mode), Assignees, Milestone. Empty rows are left out.
  - **Description:** "mira opened · 2 days ago" with a 20 pt avatar, then the body as Markdown. Bodies over 600 characters or 12 lines are cut at 160 pt with a fade and a Show More link.
  - **Conversation:** the last 10 comments and reviews, oldest first, each with avatar, login, verb ("commented", "approved", "requested changes"), relative time (links to the comment) and the Markdown body indented under the avatar. Reviews without a body are a single event line with their Octicon. "View all N on GitHub" sits next to the heading when there are more. Discussion answers carry an Answer capsule, and an answered discussion's header reads "Answered".
  - While loading: a redacted skeleton of the status grid and description. On failure: "Couldn't load the conversation" with Retry, and the basic preview below.
- Everything else (and discussions the token can't read) shows a preview of the latest comment, or the subject body if there are no comments.
- Markdown is rendered natively (`AttributedString(markdown:)` with `.full` syntax). Images and HTML become links. The text is selectable.
- Avatars load only from GitHub hosts (§12 link rules); otherwise, and while loading, they show the login's initial on a colour derived from the login.
- Security threads list their alerts: package, severity capsule, summary and GHSA ID. Each one links out.

**Bottom bar:**
- Open on GitHub (↩ or ⌘↩, the same chord as in the list; ⌥↩ or ⌥⌘↩ opens without marking read)
- Mark as Read
- Done
- An `ellipsis.circle` overflow menu with Copy Link, Mute Thread and Mute Repository. This puts every context-menu action in the main UI too.

**Reading:**
- Opening Quick Look marks the thread read, as opening an email does, wherever it was opened from (including the banner's Quick Look action). The row stays in the list.
- Only Space peeks without marking read. Mark as Read in the bottom bar is for a peeked thread.

**Focus return:**
- Before the panel opens, Tidy records `NSWorkspace.shared.frontmostApplication`, unless that app is Tidy itself.
- When the panel closes, Tidy calls `.activate()` on that app, but only if Tidy is still frontmost. If the user clicked into another app, or Open on GitHub handed focus to the browser, Tidy leaves focus alone.

**When the fetch fails:**
- The preview shows "Couldn't load details" with a Retry button.
- The header shows the base glyph in grey with "State unavailable".

## 8. States

| State | Panel | Label |
|---|---|---|
| First run, no token | Centred `tray`, "Connect GitHub", and a **Connect…** button that opens Settings › GitHub | `tray` |
| First load | A centred `ProgressView` | `tray` |
| First load while offline | Centred `wifi.slash`, "Can't reach GitHub", **Retry** | `tray` |
| Token can't be read from the Keychain | Before the first load: centred `key.slash`, "Can't read your token from the Keychain", **Retry**. After it: the same text and **Retry** in the footer. Every poll retries the read | `tray`, then last count |
| Inbox zero | `checkmark.circle`, "You're all caught up" | `tray` |
| Empty because of a filter | "No unread in owner/repo", **Clear Filter** | count |
| Offline | The cached list stays usable. The footer shows `wifi.slash` "Offline · updated 12:04" | last count |
| Rate limited (403 or 429 with `X-RateLimit-Remaining: 0` or `Retry-After`) | Footer: "GitHub rate limit · resumes 14:32". Polling pauses | last count |
| SSO required (403 with `X-GitHub-SSO`) | Footer: "Authorize token for {org}", linking to the SSO URL. The affected rows show grey glyphs | count |
| 5xx or decode error | Retries back off from 60 to 120 to 300 s. After the third failure: "GitHub isn't responding · Retry" | last count |
| 401: token invalid or revoked | `exclamationmark.triangle`, "Your GitHub token is no longer valid", **Update Token…** | `tray` |
| Token lacks the `repo` scope | "Token needs the repo scope", **Create Token…** | `tray` |

## 9. Keyboard and mouse

| Key | Action |
|---|---|
| ↑ ↓ | Move the selection. In Quick Look, step to the previous or next thread |
| Space | Peek: open Quick Look without marking read, or close it |
| ↩ | Open Quick Look for the selected row and mark it read, exactly like a click. Does nothing unless exactly one row is selected. In Quick Look: Open on GitHub and mark read |
| ⌘↩ | Open on GitHub and mark read. Opening a thread means you're handling it, as in Mail. Does nothing with more than 10 rows selected |
| ⌥⌘↩ | Open on GitHub without marking read (⌥↩ also works in Quick Look) |
| E | Done (archive) |
| ⇧I / ⇧⌘I | Mark as Read / Mark All as Read |
| ⌘A / ⌘Z | Select all / Undo |
| ⌘R | Refresh |
| ⌘1 / ⌘2 | Switch to Unread / All |
| Esc | Close Quick Look, otherwise close the panel |
| ⌘, | Open Settings |

**Hover:** two plain trailing 24 pt buttons fade in, secondary colour with a pointing-hand cursor and tooltips: `envelope.open` (Mark as Read) and `checkmark` (Done). Rows keep that space free so titles never sit under them. Rows have no separators.

**Swipe:** as in Mail, swiping right reveals the leading action, Mark as Read, and swiping left reveals the trailing action, Done.

**Context menu:**
- Quick Look, Open on GitHub, Copy Link
- Mark as Read, Done
- Mute Thread, Mute Repository

## 10. macOS notifications

**Defaults:**
- Banners are on for every reason by default.
- Tidy asks for permission after the token's first successful validation, not at launch.

**When a banner fires:** for each thread whose `updated_at` is newer than the baseline, as long as the thread is:
- unread
- not hidden or muted by a filter
- for a reason that's enabled

**No burst at startup:** the first successful fetch after launch, or after a token change, only sets the baseline. It sends no banners.

**Rules that need subject data:** if a rule depends on subject data (§11), the banner waits for that fetch, up to 5 s.

**While the panel is open,** no banners are sent. New rows animate into the list instead.

**Content:**
- **Title:** the thread title.
- **Subtitle:** `owner/repo · Review requested`.
- **Body:** the first line of the latest comment.
- **`threadIdentifier`:** the repo, so Notification Center groups banners by repo.
- **`hiddenPreviewsBodyPlaceholder`:** "New GitHub activity".
- **Summary:** when more than 5 threads are new, a single summary banner says "7 new notifications". Clicking it opens the panel.

**Clicks and buttons:**
- Clicking a banner opens the thread on GitHub and marks it read.
- The banner has three buttons:
  - **Quick Look** (`eye`): opens the panel in Quick Look, using the focus return from §7. Like any open, it marks the thread read.
  - **Mark as Read** (`envelope.open`)
  - **Done** (`checkmark`)

**Cleanup:** once a thread is read or Done, Tidy removes its delivered banner.

**Opening the panel from code** (needed for the banner's Quick Look and for reopen):
- Tidy calls `performClick` on the status item's button.
- If that fails, it shows the same view in a `Window` placed at the top right. Check this early in development.

## 11. Filters (local rules)

Filters are lightweight, Mail-style rules.
- Each rule has one or more conditions, all of which must match, and one action.
- Rules apply in order, and the first match wins.
- Rules affect the inbox, the count and banners together.

| Condition | Values | Needs a subject fetch |
|---|---|---|
| Repository or Organization is / is not | A picker of repos Tidy has seen, plus free text | no |
| Reason is | Any reason the API returns | no |
| Type is | Pull Request, Issue, Security Alert, Release, Discussion, CI, Commit | no |
| Author is | A login, with presets for `dependabot[bot]` and `renovate[bot]` | yes |
| State is | Open, Draft, Merged, Closed, Not Planned | yes |

| Action | Inbox | Counted | Notifies | GitHub call |
|---|---|---|---|---|
| Hide (default) | Hidden (footer Show reveals it) | no | no | none |
| Don't Notify | Shown | yes | no | none |
| Hide and Mark Read (opt-in) | Hidden | no | no | `PATCH` |
| Hide and Mark Done (opt-in) | Hidden | no | no | `DELETE` |

The two opt-in actions show a warning in the rule editor, and they only act on threads that arrive after the rule is saved.

**Muting:**
- **Mute Repository** adds the rule "Repository is X → Hide".
- **Mute Thread** calls `PUT /notifications/threads/{id}/subscription` with `{ignored: true}`, then archives the thread like Done (`DELETE`). It leaves the list and can be undone in the same window. Being unsubscribed, it only comes back for activity that still notifies you, such as a mention.
- Muted threads are stored locally and listed at the bottom of the Filters tab.
- **Unmute** calls `PUT …/subscription` with `{ignored: false}`.

## 12. Settings

The standard `Settings` scene with toolbar tabs, about 480 pt wide.

| Tab | Controls |
|---|---|
| General | Launch at Login (`SMAppService.mainApp`), the Menu Bar picker, Automatically check for updates (on by default: at launch, every 24 h and on wake), **Check for Updates** |
| GitHub | When signed out: a `SecureField` labelled "Personal access token (classic)", a **Create Token…** link to `https://github.com/settings/tokens/new?scopes=notifications,repo&description=Tidy`, and **Connect**. Connect calls `GET /user` and requires `repo` in `X-OAuth-Scopes`. A token that starts with `github_pat_` is rejected inline before any network call: "Fine-grained tokens can't read notifications. Use a classic token." Other errors also show inline under the field. When signed in: avatar, login, a scope checklist, **Replace Token…** and **Disconnect**. The token lives in the Keychain (generic password, this device only) |
| Notifications | The system permission status, with **Open System Settings…** for sound, style and turning banners off. A "Notify for" checklist of every reason, all on by default, grouped as Participating, Security and Activity |
| Filters | The rule list (+ and −, drag to reorder), a sheet for editing a rule, and the muted threads |
| About | Icon, name, version, and a GitHub link |

The "Notify for" list covers reasons only. Filters handle everything else.

**Connect…** and **Update Token…** in the panel open Settings on the GitHub tab.

**Updates:** a scheduled check downloads a newer release quietly and never interrupts: the panel footer and the ⋯ menu then offer **Install X**. Only a manual check shows an alert.

**Links:** the panel, Quick Look and banners open only `https` links on `github.com`, its subdomains and `*.githubusercontent.com`. Anything else in a comment body is ignored.
