import AgentBoardCore
import SwiftUI

/// Compact panel modelled on the SystemOS reference: a big count, a segmented
/// control, a mini timeline, a "needs you" callout with inline actions, and
/// dense rows with right-aligned durations.
struct MenuBarPanel: View {
    enum Segment: String, CaseIterable, Identifiable {
        case needsYou = "Needs you"
        case working = "Working"
        case ready = "Ready"
        var id: String { rawValue }
        var column: BoardColumn {
            switch self {
            case .needsYou: .waiting
            case .working: .working
            case .ready: .ready
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var segment: Segment = .needsYou

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
            hero
                .padding(.horizontal, 16)
                .padding(.top, 10)
            SoftSegmentedControl(label: "Show", options: Segment.allCases, selection: $segment) { segment in
                let count = model.board.count(segment.column)
                return count > 0 ? "\(segment.rawValue) \(count)" : segment.rawValue
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ActivityTimeline(blocks: model.timelineBlocks(), now: model.now, style: .compact)
                .padding(.horizontal, 16)
                .padding(.top, 14)

            list
                .padding(.top, 14)

            footer
        }
        .frame(width: 368)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            AppMark(size: 20)
                .accessibilityHidden(true)
            Text("Agent Board")
                .font(.callout.weight(.semibold))
            Spacer()
            if let updated = model.lastUpdated {
                Text("Updated \(Format.ago(updated, now: model.now) == "now" ? "just now" : Format.ago(updated, now: model.now) + " ago")")
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }
            Button {
                Task { await model.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.isRefreshing ? 180 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
    }

    private var hero: some View {
        let waiting = model.board.count(.waiting)
        return HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(waiting)")
                    .font(.system(size: 46, weight: .semibold).monospacedDigit())
                    .foregroundStyle(waiting > 0 ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText(value: Double(waiting)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(waiting == 1 ? "task waiting" : "tasks waiting")
                        .font(.callout.weight(.medium))
                    Text("\(model.board.count(.working)) working · \(model.board.count(.ready)) ready")
                        .font(Theme.monoSmall)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            PillButton(title: "Board", symbol: "rectangle.split.3x1") {
                openBoard(selecting: nil)
            }
            .accessibilityLabel("Open board")
        }
    }

    @ViewBuilder
    private var list: some View {
        let tasks = model.board.tasks(in: segment.column)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(segment == .needsYou && !tasks.isEmpty ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                Text(callout(count: tasks.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            if let first = tasks.first {
                FeaturedTask(task: first, segment: segment) { openBoard(selecting: first) }
                    .padding(.horizontal, 10)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(tasks.dropFirst().prefix(12)) { task in
                            PanelRow(task: task) { openBoard(selecting: task) }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(maxHeight: 214)
                .scrollIndicators(.never)
                .mask {
                    // Fade the last row when the list scrolls, instead of a hard cut.
                    VStack(spacing: 0) {
                        Color.black
                        if tasks.count > 6 {
                            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 28)
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tertiary)
                    Text(segment.column.emptyMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
            }
        }
        .padding(.bottom, 8)
    }

    private var footer: some View {
        let github = model.statuses.first { $0.kind == .github }
        return VStack(spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            HStack(spacing: 8) {
                if let github {
                    HealthIcon(health: github.health).font(.caption)
                    Text(github.health == .ok ? "gh signed in · \(model.board.tasks.count) tasks" : github.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    model.screen = .settings
                    openWindow(id: "main")
                    NSApp.activate()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func callout(count: Int) -> String {
        switch segment {
        case .needsYou: count == 0 ? "Nothing needs you" : "\(count) task\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") you"
        case .working: count == 0 ? "No agent is working" : "\(count) agent\(count == 1 ? " is" : "s are") working"
        case .ready: count == 0 ? "Nothing to merge" : "\(count) ready to merge"
        }
    }

    private func openBoard(selecting task: BoardTask?) {
        model.screen = .board
        if let task {
            model.select(task)
            model.inspectorOpen = true
        }
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// The highlighted top task with inline actions (the reference's review callout).
private struct FeaturedTask: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    let segment: MenuBarPanel.Segment
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(task.apps.first?.tint ?? Theme.accent).frame(width: 7, height: 7)
                if let date = task.lastActivity {
                    Text(Format.shortWhen(date, now: model.now))
                        .font(Theme.monoSmall)
                        .foregroundStyle(.secondary)
                }
                Text(task.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Format.ago(task.lastActivity ?? task.pullRequest?.updatedAt, now: model.now))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.secondary)
            }
            Text(task.locationLine)
                .font(Theme.monoSmall)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 15)
            HStack(spacing: 6) {
                if let session = task.onBranchSessions.first ?? task.sessions.first, session.resumeCommand != nil {
                    Button("Copy resume") { model.copyResumeCommand(session) }
                        .buttonStyle(PanelActionStyle())
                }
                if task.directory != nil {
                    Button("Open folder") { model.openFolder(task) }
                        .buttonStyle(PanelActionStyle())
                }
                Spacer()
                if task.pullRequest?.url != nil {
                    Button("Open PR") { model.openPullRequest(task) }
                        .buttonStyle(PanelActionStyle(prominent: true))
                } else {
                    Button("Details") { open() }
                        .buttonStyle(PanelActionStyle(prominent: true))
                }
            }
            .padding(.leading, 15)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(TaskCard.accessibilityDescription(task, now: model.now))
    }
}

private struct PanelRow: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(task.apps.first == .claude ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                Text(task.lastActivity.map { Format.shortWhen($0, now: model.now) } ?? "—")
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
                    .frame(width: 58, alignment: .leading)
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(Format.ago(task.lastActivity ?? task.pullRequest?.updatedAt, now: model.now))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(hovered ? 0.07 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu { TaskActionsMenu(task: task) }
        .accessibilityLabel(TaskCard.accessibilityDescription(task, now: model.now))
    }

    private var icon: String {
        if task.apps.count > 1 { return "square.on.square" }
        return task.apps.first == .codex ? "chevron.left.forwardslash.chevron.right" : "sparkle"
    }
}

private struct PanelActionStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.09)))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
