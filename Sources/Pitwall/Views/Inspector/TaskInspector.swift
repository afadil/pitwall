import PitwallCore
import SwiftUI

/// Details and actions for the selected task.
struct TaskInspector: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                organizeSection
                if let pr = task.pullRequest {
                    pullRequestSection(pr)
                }
                if let stack = task.stack, let pr = task.pullRequest {
                    stackSection(stack, current: pr.number)
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
            if let session = task.sessionToOpen, session.appURL != nil {
                PillButton(title: "Open in \(session.app.displayName)", symbol: "arrow.up.forward.app") {
                    model.openInApp(session)
                }
                .padding(.top, 4)
            }
        }
    }

    /// Lane and tags: yours, stored in organization.json.
    private var organizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Lane")
            SoftSegmentedControl(label: "Lane", options: Lane.allCases,
                                 selection: Binding(get: { task.lane }, set: { model.setLane($0, for: task) })) { $0.title }
            if task.stack != nil {
                Text("Moves the whole stack.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            SectionHeader("Tags") {
                Menu {
                    let unused = model.organization.tags.filter { !model.hasTag($0, task) }
                    ForEach(unused) { tag in
                        Button {
                            model.setTag(tag, on: true, for: task)
                        } label: {
                            Label { Text(tag.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(tag.color.color) }
                        }
                    }
                    if !unused.isEmpty { Divider() }
                    Button("New tag…") { model.beginNewTag(for: task) }
                } label: {
                    Label("Add", systemImage: "plus").font(.caption.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Add tag")
            }
            if task.tags.isEmpty && task.labels.isEmpty {
                Text("No tags. Add as many as you like, then filter the board by them.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(task.tags) { tag in
                        TagChip(tag: tag) { model.setTag(tag, on: false, for: task) }
                    }
                    ForEach(task.labels, id: \.name) { LabelChip(label: $0) }
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

    /// The stack bottom first, with this PR highlighted and the one being worked on marked.
    private func stackSection(_ stack: StackInfo, current: Int) -> some View {
        let working = stack.workingVia ?? (task.column == .working ? current : nil)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Stack · \(stack.members.count)")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stack.members.enumerated()), id: \.element) { index, number in
                    let peer = model.board.tasks.first { $0.pullRequest?.number == number && $0.pullRequest?.repo == task.pullRequest?.repo }
                    HStack(spacing: 8) {
                        Image(systemName: index == 0 ? "circle.fill" : "arrow.turn.left.up")
                            .font(.system(size: index == 0 ? 5 : 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                        Text(verbatim: "#\(number)")
                            .font(Theme.monoMedium)
                            .foregroundStyle(number == current ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
                        Text(peer?.pullRequest?.title ?? (number == current ? task.title : "Not on the board"))
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(number == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        Spacer(minLength: 4)
                        if number == working {
                            PulseDot(size: 5).frame(width: 12, height: 12)
                                .help("A session is working on this one")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(number == current ? Theme.accent.opacity(0.08) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if let peer { model.select(peer) } }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(number == current ? [.isSelected] : [])
                }
            }
            .surface()
            Text(stackNote(stack))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stackNote(_ stack: StackInfo) -> String {
        if let via = stack.workingVia {
            return "A session is working on #\(via) in this stack, so the stack counts as in progress."
        }
        if let base = stack.base {
            return "Targets #\(base)'s branch, so it lands after #\(base)."
        }
        return "Bottom of the stack: targets the default branch."
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(task.sessions.count == 1 ? "Session" : "Sessions · \(task.sessions.count)")
            VStack(spacing: 0) {
                ForEach(Array(task.sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 12) }
                    SessionRow(session: session, linked: task.linkedSessionIDs.contains(session.id), showOpen: task.sessions.count > 1)
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
