import SwiftUI
import TidyCore

struct ThreadDetailsView: View {
    let details: ThreadDetails?
    let kind: SubjectKind
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if let details {
            VStack(alignment: .leading, spacing: 20) {
                status(of: details)
                DescriptionSection(details: details)
                if !details.timeline.isEmpty {
                    Divider()
                    ConversationSection(details: details, kind: kind)
                }
            }
        } else {
            skeleton
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 20) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    SectionLabel(title: "Reviews")
                    Text("Approved by two reviewers")
                }
                GridRow {
                    SectionLabel(title: "Checks")
                    Text("4 checks passed")
                }
                GridRow {
                    SectionLabel(title: "Labels")
                    Text("enhancement, ui")
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Description of the change").font(.headline)
                Text("A placeholder paragraph that stands in for the body while it loads from GitHub.")
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading details")
    }

    @ViewBuilder private func status(of details: ThreadDetails) -> some View {
        let pull = details.pullRequest
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 12) {
            if let pull {
                GridRow {
                    SectionLabel(title: "Branch")
                    VStack(alignment: .leading, spacing: 6) {
                        FlowLayout(spacing: 4) {
                            branchChip(pull.baseBranch)
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left").imageScale(.small).foregroundStyle(.secondary)
                                branchChip(pull.headBranch)
                            }
                        }
                        HStack(spacing: 4) {
                            Text("+\(pull.additions)").foregroundStyle(StateGlyphView.color(for: .green, scheme: scheme, contrast: contrast))
                            Text("−\(pull.deletions)").foregroundStyle(StateGlyphView.color(for: .red, scheme: scheme, contrast: contrast))
                            Text("· \(pull.changedFiles) \(pull.changedFiles == 1 ? "file" : "files")").foregroundStyle(.secondary)
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
                if !pull.reviewers.isEmpty || pull.reviewDecision != nil {
                    GridRow {
                        SectionLabel(title: "Reviews")
                        VStack(alignment: .leading, spacing: 4) {
                            if let decision = pull.reviewDecision {
                                Text(decision.title).font(.subheadline.weight(.semibold))
                            }
                            FlowLayout(spacing: 4) {
                                ForEach(pull.reviewers) { reviewer in
                                    ReviewerChip(reviewer: reviewer)
                                }
                            }
                        }
                    }
                }
                if let checks = pull.checks {
                    GridRow {
                        SectionLabel(title: "Checks")
                        checksLine(checks)
                    }
                }
                if pull.hasConflicts {
                    GridRow {
                        SectionLabel(title: "Merge")
                        Label {
                            Text("Conflicts with \(pull.baseBranch)")
                        } icon: {
                            Image(Octicon.alert.rawValue).foregroundStyle(StateGlyphView.color(for: .orange, scheme: scheme, contrast: contrast))
                        }
                        .font(.subheadline)
                    }
                }
            }
            if let discussion = details.discussion, let category = discussion.category {
                GridRow {
                    SectionLabel(title: "Category")
                    Text(category).font(.subheadline)
                }
            }
            if !details.labels.isEmpty {
                GridRow {
                    SectionLabel(title: "Labels")
                    FlowLayout(spacing: 4) {
                        ForEach(details.labels) { label in
                            LabelCapsule(label: label)
                        }
                    }
                }
            }
            if !details.assignees.isEmpty {
                GridRow {
                    SectionLabel(title: "Assignees")
                    FlowLayout(spacing: 8) {
                        ForEach(details.assignees, id: \.login) { user in
                            HStack(spacing: 4) {
                                AvatarView(user: user, size: 16)
                                Text(user.login)
                            }
                            .font(.subheadline)
                        }
                    }
                }
            }
            if let milestone = details.milestone {
                GridRow {
                    SectionLabel(title: "Milestone")
                    Text(milestone).font(.subheadline)
                }
            }
        }
    }

    private func branchChip(_ name: String) -> some View {
        Text(name)
            .font(.system(.caption, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.12), in: .rect(cornerRadius: 6))
            .help(name)
    }

    private func checksLine(_ checks: CheckSummary) -> some View {
        let (octicon, tone): (Octicon, StateTone) =
            switch checks.state {
            case .success: (.checkCircle, .green)
            case .failure: (.xCircle, .red)
            case .pending: (.dotFill, .yellow)
            }
        return Label {
            Text(checks.summary).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(octicon.rawValue).foregroundStyle(StateGlyphView.color(for: tone, scheme: scheme, contrast: contrast))
        }
        .font(.subheadline)
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(width: 72, alignment: .leading)
    }
}

private struct DescriptionSection: View {
    let details: ThreadDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CommentHeader(author: details.author, action: "opened", date: details.createdAt)
            if details.body.isEmpty {
                Text("No description provided.").foregroundStyle(.secondary)
            } else {
                MarkdownView(source: details.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ConversationSection: View {
    let details: ThreadDetails
    let kind: SubjectKind
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Conversation").font(.headline)
                Spacer()
                if details.hasOlderComments, let url = details.url {
                    Link("View all \(details.totalComments) comments on GitHub", destination: url)
                        .font(.subheadline)
                }
            }
            ForEach(details.timeline) { entry in
                switch entry {
                case .event(let event):
                    TimelineEventRow(event: event, subjectKind: kind)
                case .comment(let comment):
                    if comment.body.isEmpty, let review = comment.review {
                        reviewEvent(comment, review: review)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            CommentHeader(author: comment.author, action: comment.review.map(Self.verb(for:)) ?? "commented", date: comment.createdAt, url: comment.url, isAnswer: comment.isAnswer)
                            MarkdownView(source: comment.body)
                                .padding(.leading, 28)
                        }
                    }
                }
            }
        }
    }

    private func reviewEvent(_ comment: TimelineComment, review: ReviewState) -> some View {
        let (octicon, tone) = ReviewerChip.appearance(of: review)
        return HStack(spacing: 8) {
            Image(octicon.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(StateGlyphView.color(for: tone, scheme: scheme, contrast: contrast))
                .frame(width: 20)
            CommentHeader(author: comment.author, action: Self.verb(for: review), date: comment.createdAt, url: comment.url, showsAvatar: false)
        }
    }

    static func verb(for review: ReviewState) -> String {
        switch review {
        case .approved: "approved"
        case .changesRequested: "requested changes"
        case .commented: "reviewed"
        case .dismissed: "review dismissed"
        case .requested: "was requested"
        }
    }
}

private struct TimelineEventRow: View {
    let event: TimelineEvent
    let subjectKind: SubjectKind
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let (icon, tone) = appearance
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                icon
                    .font(.system(size: 12))
                    .foregroundStyle(StateGlyphView.color(for: tone, scheme: scheme, contrast: contrast))
                    .frame(width: 20)
                CommentHeader(author: event.actor, action: verb, date: event.date, showsAvatar: false)
            }
            detail
                .font(.subheadline)
                .padding(.leading, 28)
        }
    }

    private var verb: String {
        let actor = event.actor?.login
        switch event.kind {
        case .committed(let commits): return commits.count == 1 ? "added a commit" : "added \(commits.count) commits"
        case .forcePushed(let branch): return branch.map { "force-pushed the \($0) branch" } ?? "force-pushed"
        case .deletedBranch(let branch): return branch.map { "deleted the \($0) branch" } ?? "deleted the branch"
        case .requestedReview(let reviewers) where reviewers.count == 1 && reviewers.first?.login == actor: return "self-requested a review"
        case .requestedReview(let reviewers) where reviewers.isEmpty: return "requested a review"
        case .requestedReview(let reviewers): return "requested a review from \(reviewers.map(\.login).formatted(.list(type: .and)))"
        case .removedReviewRequest(let reviewer): return reviewer.map { "removed the review request for \($0.login)" } ?? "removed a review request"
        case .merged(let branch): return branch.map { "merged into \($0)" } ?? "merged this"
        case .closed: return "closed this"
        case .reopened: return "reopened this"
        case .readyForReview: return "marked this ready for review"
        case .convertedToDraft: return "converted this to a draft"
        case .labeled: return "added a label"
        case .unlabeled: return "removed a label"
        case .assigned(let user): return user.login == actor ? "self-assigned this" : "assigned \(user.login)"
        case .unassigned(let user): return user.login == actor ? "removed their assignment" : "unassigned \(user.login)"
        case .renamed: return "changed the title"
        case .crossReferenced: return "mentioned this"
        }
    }

    private var appearance: (Image, StateTone) {
        switch event.kind {
        case .committed: (Image(Octicon.gitCommit.rawValue), .grey)
        case .forcePushed: (Image(systemName: "arrow.triangle.branch"), .grey)
        case .deletedBranch: (Image(systemName: "trash"), .grey)
        case .requestedReview: (Image(systemName: "eye"), .grey)
        case .removedReviewRequest: (Image(systemName: "eye.slash"), .grey)
        case .merged: (Image(Octicon.gitMerge.rawValue), .purple)
        case .closed: subjectKind == .pullRequest ? (Image(Octicon.gitPullRequestClosed.rawValue), .red) : (Image(Octicon.issueClosed.rawValue), .purple)
        case .reopened: (Image((subjectKind == .pullRequest ? Octicon.gitPullRequest : .issueOpened).rawValue), .green)
        case .readyForReview: (Image(Octicon.gitPullRequest.rawValue), .green)
        case .convertedToDraft: (Image(Octicon.gitPullRequestDraft.rawValue), .grey)
        case .labeled, .unlabeled: (Image(Octicon.tag.rawValue), .grey)
        case .assigned: (Image(Octicon.personAdd.rawValue), .grey)
        case .unassigned: (Image(systemName: "person.badge.minus"), .grey)
        case .renamed: (Image(systemName: "pencil"), .grey)
        case .crossReferenced: (Image(systemName: "link"), .grey)
        }
    }

    @ViewBuilder private var detail: some View {
        switch event.kind {
        case .committed(let commits):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(commits, id: \.shortSHA) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(commit.shortSHA)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(commit.headline).lineLimit(1)
                    }
                }
            }
        case .labeled(let label), .unlabeled(let label):
            LabelCapsule(label: label)
        case .renamed(let old, let new):
            Text("\(Text(old).strikethrough().foregroundStyle(.secondary)) \(Text(Image(systemName: "arrow.right")).foregroundStyle(.secondary)) \(new)")
                .fixedSize(horizontal: false, vertical: true)
        case .crossReferenced(let reference):
            let text = Text("\(Text("\(reference.repository)#\(reference.number)").foregroundStyle(.secondary)) \(reference.title)")
            if let url = reference.url, url.isGitHubWeb {
                Link(destination: url) { text.multilineTextAlignment(.leading) }
                    .buttonStyle(.plain)
            } else {
                text
            }
        default:
            EmptyView()
        }
    }
}

private struct CommentHeader: View {
    let author: GitHubUser?
    let action: String
    let date: Date?
    var url: URL? = nil
    var showsAvatar = true
    var isAnswer = false

    var body: some View {
        HStack(spacing: 8) {
            if showsAvatar { AvatarView(user: author, size: 20) }
            HStack(spacing: 4) {
                Text(author?.login ?? "ghost").fontWeight(.semibold).layoutPriority(1)
                Text(action).foregroundStyle(.secondary).truncationMode(.middle)
                if let date {
                    Text("·").foregroundStyle(.secondary).layoutPriority(1)
                    timestamp(date).layoutPriority(1)
                }
            }
            .lineLimit(1)
            if isAnswer {
                Text("Answer")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.16), in: .capsule)
            }
        }
        .font(.subheadline)
    }

    @ViewBuilder private func timestamp(_ date: Date) -> some View {
        let text = Text(date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
        if let url {
            Link(destination: url) { text }
                .foregroundStyle(.secondary)
                .help(date.formatted(date: .complete, time: .shortened))
        } else {
            text
                .foregroundStyle(.secondary)
                .help(date.formatted(date: .complete, time: .shortened))
        }
    }
}

private struct ReviewerChip: View {
    let reviewer: Reviewer
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    static func appearance(of state: ReviewState) -> (Octicon, StateTone) {
        switch state {
        case .approved: (.check, .green)
        case .changesRequested: (.fileDiff, .red)
        case .commented: (.comment, .grey)
        case .dismissed: (.comment, .grey)
        case .requested: (.dotFill, .yellow)
        }
    }

    var body: some View {
        let (octicon, tone) = Self.appearance(of: reviewer.state)
        HStack(spacing: 4) {
            AvatarView(user: reviewer.user, size: 16)
            Text(reviewer.user.login)
            Image(octicon.rawValue)
                .font(.system(size: 12))
                .foregroundStyle(StateGlyphView.color(for: tone, scheme: scheme, contrast: contrast))
        }
        .font(.subheadline)
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: .capsule)
        .help("\(reviewer.user.login): \(reviewer.state.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reviewer.user.login), \(reviewer.state.title)")
    }
}

struct AvatarView: View {
    let user: GitHubUser?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = user?.avatarURL, url.isGitHubWeb {
                AsyncImage(url: url) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        let login = user?.login ?? "?"
        let hue = Double(login.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 360) / 360
        return Circle()
            .fill(Color(hue: hue, saturation: 0.45, brightness: 0.8).gradient)
            .overlay {
                Text(login.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
    }
}

private struct LabelCapsule: View {
    let label: IssueLabel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hex = UInt32(label.color, radix: 16) ?? 0xededed
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 8) & 0xff) / 255
        let blue = Double(hex & 0xff) / 255
        let base = Color(red: red, green: green, blue: blue)
        let isLight = 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
        let text: Color = scheme == .dark ? base.mix(with: .white, by: 0.4) : (isLight ? .black.opacity(0.85) : .white)
        Text(label.name)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(text)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(scheme == .dark ? base.opacity(0.2) : base, in: .capsule)
            .overlay(Capsule().strokeBorder(base.opacity(scheme == .dark ? 0.4 : 0), lineWidth: 1))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight + spacing)
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: CGSize(width: min(size.width, width), height: size.height)))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}
