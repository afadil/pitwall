import AgentBoardCore
import SwiftUI

/// A task card: apps, title, `repo · branch`, and PR / CI / review state.
struct TaskCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: BoardTask
    @State private var hovered = false

    var body: some View {
        let selected = model.selectedTaskID == task.id
        VStack(alignment: .leading, spacing: 8) {
            topRow
            Text(task.title)
                .font(.system(.callout, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            LocationLine(task: task)
            if let problem = task.problems.first {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(WarningLabelStyle())
            }
            if let pr = task.pullRequest {
                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                prRow(pr)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(hovered: hovered, selected: selected)
        .opacity(task.isHidden ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        // Click selects and shows details; double-click opens the session in its app.
        .gesture(TapGesture(count: 2).onEnded { model.openInApp(task) })
        .simultaneousGesture(TapGesture().onEnded {
            model.select(task)
            model.inspectorOpen = true
        })
        .help(task.sessionToOpen.map { "Double-click to open in \($0.app.displayName)" } ?? "")
        .contextMenu { TaskActionsMenu(task: task) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityDescription(task, now: model.now))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(task); model.inspectorOpen = true }
        .accessibilityActions { TaskAccessibilityActions(task: task) }
    }

    private var topRow: some View {
        HStack(spacing: 5) {
            ForEach(task.apps, id: \.self) { AppBadge(app: $0) }
            if task.isHidden {
                Text("Hidden")
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            if hovered {
                quickActions
                    .transition(.opacity)
            } else {
                activity
                    .transition(.opacity)
            }
        }
        .frame(height: 20)
    }

    @ViewBuilder
    private var activity: some View {
        HStack(spacing: 4) {
            if task.column == .working {
                PulseDot(size: 5).frame(width: 12, height: 12)
            }
            Text(Format.ago(task.lastActivity ?? task.pullRequest?.updatedAt, now: model.now))
                .font(Theme.monoSmall)
                .foregroundStyle(task.column == .working ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.tertiary))
        }
    }

    private var quickActions: some View {
        HStack(spacing: 4) {
            if let session = task.sessionToOpen, session.appURL != nil {
                SoftIconButton(symbol: "arrow.up.forward.app", label: "Open in \(session.app.displayName)", size: 22) {
                    model.openInApp(session)
                }
            }
            if task.pullRequest?.url != nil {
                SoftIconButton(symbol: "arrow.up.right", label: "Open pull request", size: 22) {
                    model.openPullRequest(task)
                }
            }
            if let session = task.onBranchSessions.first ?? task.sessions.first, session.resumeCommand != nil {
                SoftIconButton(symbol: "terminal", label: "Copy resume command", size: 22) {
                    model.copyResumeCommand(session)
                }
            }
            if task.directory != nil {
                SoftIconButton(symbol: "folder", label: "Open folder", size: 22) {
                    model.openFolder(task)
                }
            }
        }
    }

    private func prRow(_ pr: PullRequest) -> some View {
        // Narrow columns drop the secondary icon rather than wrapping the pill.
        ViewThatFits(in: .horizontal) {
            prRowContent(pr, showSecondary: true)
            prRowContent(pr, showSecondary: false)
        }
    }

    private func prRowContent(_ pr: PullRequest, showSecondary: Bool) -> some View {
        HStack(spacing: 10) {
            PRChip(pr: pr).fixedSize()
            if let reason = task.reviewReason {
                ReasonPill(reason: reason).fixedSize()
            } else if pr.state == .open {
                StatusLabel(symbol: pr.checks.state.symbol, text: pr.checks.state.label, color: pr.checks.state.color).fixedSize()
            }
            Spacer(minLength: 0)
            if showSecondary { secondarySignal(pr) }
        }
    }

    /// The signal the left side doesn't already show: review decision next to a CI
    /// state, or CI state next to a review-related reason.
    @ViewBuilder
    private func secondarySignal(_ pr: PullRequest) -> some View {
        if pr.state == .open {
            switch task.reviewReason {
            case .draft?, .changesRequested?, .awaitingReview?:
                if pr.checks.state != .none {
                    signalIcon(pr.checks.state.symbol, pr.checks.state.color, pr.checks.state.label)
                }
            case .ciFailing?, .ciRunning?, nil:
                if let review = pr.reviewDecision.label {
                    signalIcon(pr.reviewDecision.symbol, pr.reviewDecision.color, review)
                }
            }
        }
    }

    private func signalIcon(_ symbol: String, _ color: Color, _ label: String) -> some View {
        Image(systemName: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .help(label)
            .accessibilityLabel(label)
    }

    static func accessibilityDescription(_ task: BoardTask, now: Date) -> String {
        var parts = [task.title]
        if let repo = task.repo { parts.append(repo.displayName) }
        if let branch = task.branch { parts.append("branch \(branch)") }
        parts.append(task.apps.map(\.displayName).joined(separator: " and "))
        parts.append(task.column.title)
        if let activity = task.lastActivity { parts.append("active \(Format.spokenAgo(activity, now: now))") }
        if let pr = task.pullRequest {
            parts.append("pull request \(pr.number), \(pr.stateLabel)")
            if let reason = task.reviewReason { parts.append(reason.label) }
            if pr.state == .open { parts.append(pr.checks.state.label) }
            if let review = pr.reviewDecision.label { parts.append(review) }
        }
        if task.isHidden { parts.append("hidden") }
        if let problem = task.problems.first { parts.append(problem) }
        return parts.joined(separator: ", ")
    }
}

/// `repo · branch`. When it doesn't fit, the repo name shortens to a prefix and the
/// branch truncates in the middle, so both stay recognisable.
private struct LocationLine: View {
    let task: BoardTask

    private var repoName: String {
        task.repo?.name ?? task.directory.map { ($0 as NSString).lastPathComponent } ?? "No repository"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(repo: repoName).fixedSize()
            line(repo: repoName.count > 7 ? String(repoName.prefix(6)) + "…" : repoName)
        }
        .font(Theme.mono)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help(task.locationLine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(task.locationLine)
    }

    private func line(repo: String) -> some View {
        HStack(spacing: 0) {
            Text(repo).fixedSize()
            if let branch = task.branch {
                Text(" · ").fixedSize()
                Text(branch).truncationMode(.middle)
            }
        }
    }
}

private struct WarningLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(Theme.pending)
            configuration.title
        }
    }
}

/// Context menu for a task. Also used by Done rows and the inspector's "More" menu.
struct TaskActionsMenu: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        let openable = task.sessions.filter { $0.appURL != nil }
        if openable.count == 1, let session = openable.first {
            Button("Open in \(session.app.displayName)", systemImage: "arrow.up.forward.app") { model.openInApp(session) }
        } else if openable.count > 1 {
            ForEach(openable) { session in
                Button("Open in \(session.app.displayName): \(session.title)", systemImage: "arrow.up.forward.app") { model.openInApp(session) }
            }
        }
        if task.pullRequest?.url != nil {
            Button("Open pull request", systemImage: "arrow.up.right.square") { model.openPullRequest(task) }
        }
        if task.directory != nil {
            Menu("Open folder", systemImage: "folder") {
                Button("In Finder") { model.openFolder(task, with: .finder) }
                Button("In Terminal") { model.openFolder(task, with: .terminal) }
                Button("In \(AppModel.editorName)") { model.openFolder(task, with: .editor) }
            }
        }
        let resumable = task.sessions.filter { $0.resumeCommand != nil }
        if resumable.count == 1, let session = resumable.first {
            Button("Copy resume command", systemImage: "terminal") { model.copyResumeCommand(session) }
        } else if resumable.count > 1 {
            Menu("Copy resume command", systemImage: "terminal") {
                ForEach(resumable) { session in
                    Button("\(session.app.displayName): \(session.title)") { model.copyResumeCommand(session) }
                }
            }
        }
        if task.branch != nil {
            Button("Copy branch name", systemImage: "doc.on.doc") { model.copyBranch(task) }
        }
        if let pr = task.pullRequest, pr.state == .open {
            Divider()
            if pr.isDraft {
                Button("Mark ready for review…", systemImage: "eye") { model.request(.markReady, for: task) }
            } else {
                Button("Merge…", systemImage: "arrow.trianglehead.merge") { model.request(.merge(.squash), for: task) }
            }
        }
        Divider()
        Button(task.isHidden ? "Show card" : "Hide card", systemImage: task.isHidden ? "eye" : "eye.slash") {
            model.toggleHidden(task)
        }
    }
}

/// VoiceOver custom actions mirroring the context menu.
struct TaskAccessibilityActions: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        if let session = task.sessionToOpen, session.appURL != nil {
            Button("Open in \(session.app.displayName)") { model.openInApp(session) }
        }
        if task.pullRequest?.url != nil {
            Button("Open pull request") { model.openPullRequest(task) }
        }
        if let session = task.sessions.first(where: { $0.resumeCommand != nil }) {
            Button("Copy resume command") { model.copyResumeCommand(session) }
        }
        if task.directory != nil {
            Button("Open folder") { model.openFolder(task) }
        }
        if let pr = task.pullRequest, pr.state == .open {
            if pr.isDraft {
                Button("Mark ready for review") { model.request(.markReady, for: task) }
            } else {
                Button("Merge") { model.request(.merge(.squash), for: task) }
            }
        }
        Button(task.isHidden ? "Show card" : "Hide card") { model.toggleHidden(task) }
    }
}
