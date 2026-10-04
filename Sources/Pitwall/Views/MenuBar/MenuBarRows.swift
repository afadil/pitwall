import PitwallCore
import SwiftUI

/// The highlighted top task with inline actions (the reference's review callout).
struct FeaturedTask: View {
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
                if task.pullRequest?.url != nil {
                    Button("Open PR") { model.openPullRequest(task) }
                        .buttonStyle(PanelActionStyle())
                }
                if let session = task.sessionToOpen, session.resumeCommand != nil {
                    Button("Copy resume") { model.copyResumeCommand(session) }
                        .buttonStyle(PanelActionStyle())
                }
                Button("Details") { open() }
                    .buttonStyle(PanelActionStyle())
                Spacer(minLength: 4)
                if let session = task.sessionToOpen, session.appURL != nil {
                    Button("Open in \(session.app.displayName)") { model.openInApp(session) }
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

/// A row: clicking opens the session in its app, the context menu offers the rest.
struct PanelRow: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    let showOnBoard: () -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            if task.sessionToOpen?.appURL != nil { model.openInApp(task) } else { showOnBoard() }
        } label: {
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
                if task.lane == .fast {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Fast lane")
                }
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
        .help(task.sessionToOpen.map { "Open in \($0.app.displayName)" } ?? "Show on the board")
        .contextMenu {
            Button("Show on board", systemImage: "rectangle.split.3x1") { showOnBoard() }
            Divider()
            TaskActionsMenu(task: task)
        }
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
