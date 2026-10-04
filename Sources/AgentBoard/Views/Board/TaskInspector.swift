import AgentBoardCore
import SwiftUI

/// Details and actions for the selected task.
struct TaskInspector: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let pr = task.pullRequest {
                    pullRequestSection(pr)
                }
                sessionsSection
                if let directory = task.directory {
                    folderSection(directory)
                }
                if !task.problems.isEmpty {
                    problemsSection
                }
                Button {
                    model.toggleHidden(task)
                } label: {
                    Label(task.isHidden ? "Show card" : "Hide card", systemImage: task.isHidden ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Task details")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ColumnPill(column: task.column)
                Spacer()
                Button {
                    model.inspectorOpen = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close details")
                .accessibilityLabel("Close details")
            }
            Text(task.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let repo = task.repo {
                Text(repo.displayName).font(Theme.mono).foregroundStyle(.secondary)
            }
            if let branch = task.branch {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.trianglehead.branch").font(.caption2).foregroundStyle(.tertiary)
                    Text(branch).font(Theme.mono).foregroundStyle(.secondary).textSelection(.enabled)
                    if task.isDefaultBranch {
                        Text("default").font(Theme.monoSmall).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func pullRequestSection(_ pr: PullRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Pull request")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PRChip(pr: pr)
                    Text(pr.stateLabel).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let updated = pr.updatedAt {
                        Text(Format.ago(updated, now: model.now)).font(Theme.monoSmall).foregroundStyle(.tertiary)
                    }
                }
                Text(pr.title)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let base = pr.baseRefName {
                    Text("\(pr.headRefName) → \(base)")
                        .font(Theme.monoSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Divider().overlay(Theme.hairline)
                checksRow(pr)
                HStack(spacing: 6) {
                    Image(systemName: pr.reviewDecision.symbol)
                        .foregroundStyle(pr.reviewDecision.color)
                        .font(.caption.weight(.semibold))
                        .frame(width: 16)
                    Text(pr.reviewDecision.label ?? "No review required")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(12)
            .surface()

            HStack(spacing: 8) {
                if pr.url != nil {
                    PillButton(title: "Open on GitHub", symbol: "arrow.up.right") { model.openPullRequest(task) }
                }
                if pr.state == .open {
                    if pr.isDraft {
                        PillButton(title: "Mark ready…", symbol: "eye", prominent: task.column == .inReview) {
                            model.request(.markReady, for: task)
                        }
                    } else {
                        PillButton(title: "Merge…", symbol: "arrow.trianglehead.merge", prominent: task.column == .ready) {
                            model.request(.merge(.squash), for: task)
                        }
                    }
                }
            }
        }
    }

    private func checksRow(_ pr: PullRequest) -> some View {
        let c = pr.checks
        var parts: [String] = []
        if c.passed > 0 { parts.append("\(c.passed) passed") }
        if c.failed > 0 { parts.append("\(c.failed) failed") }
        if c.pending > 0 { parts.append("\(c.pending) running") }
        if c.skipped > 0 { parts.append("\(c.skipped) skipped") }
        return HStack(spacing: 6) {
            Image(systemName: c.state.symbol)
                .foregroundStyle(c.state.color)
                .font(.caption.weight(.semibold))
                .frame(width: 16)
            Text(parts.isEmpty ? "No checks" : parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(task.sessions.count == 1 ? "Session" : "Sessions · \(task.sessions.count)")
            VStack(spacing: 0) {
                ForEach(Array(task.sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 12) }
                    SessionRow(session: session, linked: task.linkedSessionIDs.contains(session.id))
                }
            }
            .surface()
        }
    }

    private func folderSection(_ directory: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Folder")
            Text(Format.path(directory))
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                SoftIconButton(symbol: "folder", label: "Open in Finder", size: 28) { model.openFolder(task, with: .finder) }
                SoftIconButton(symbol: "apple.terminal", label: "Open in Terminal", size: 28) { model.openFolder(task, with: .terminal) }
                SoftIconButton(symbol: "chevron.left.forwardslash.chevron.right", label: "Open in \(AppModel.editorName)", size: 28) {
                    model.openFolder(task, with: .editor)
                }
            }
        }
    }

    private var problemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Can't read")
            ForEach(task.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SessionRow: View {
    @Environment(AppModel.self) private var model
    let session: AgentSession
    let linked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppBadge(app: session.app)
                Text(state)
                    .font(.caption)
                    .foregroundStyle(session.turn == .running ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
                Spacer()
                Text(Format.ago(session.lastActivity, now: model.now))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }
            Text(session.title)
                .font(.callout)
                .lineLimit(2)
            if linked {
                Text("Opened this pull request, now on \(session.branch ?? "another branch")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let command = session.resumeCommand {
                Button {
                    model.copyResumeCommand(session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal").font(.caption2)
                        Text(command.components(separatedBy: " && ").last ?? command)
                            .font(Theme.monoSmall)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Image(systemName: "doc.on.doc").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy: \(command)")
                .accessibilityLabel("Copy \(session.app.displayName) resume command")
            }
        }
        .padding(12)
    }

    private var state: String {
        switch session.turn {
        case .running: "Turn running"
        case .ended: session.isArchived ? "Archived" : "Turn ended"
        case .unknown: "State unknown"
        }
    }
}

struct ColumnPill: View {
    let column: BoardColumn

    var body: some View {
        HStack(spacing: 5) {
            if column == .working {
                PulseDot(size: 5).frame(width: 10, height: 10)
            } else {
                Image(systemName: column.symbol).font(.system(size: 9, weight: .bold))
            }
            Text(column.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(column == .working || column == .waiting ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(column == .working || column == .waiting ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.07)))
        .accessibilityElement(children: .combine)
    }
}
