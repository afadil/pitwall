import PitwallCore
import SwiftUI

/// One horizontal band: header, then a cell per column.
struct LaneSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let row: BoardRow
    let columns: [BoardColumn]
    let columnWidth: CGFloat
    let spacing: CGFloat
    @Binding var collapsed: Bool
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !collapsed {
                if row.tasks.filter({ $0.column != .done }).isEmpty {
                    emptyHint
                } else {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(columns) { column in
                            LaneCell(row: row, column: column)
                                .frame(width: columnWidth)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    targeted ? Theme.accent : (row.isFastLane ? Theme.accent.opacity(0.22) : .clear),
                    style: StrokeStyle(lineWidth: targeted ? 1.5 : 0.5, dash: targeted ? [5, 4] : []))
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(Theme.animation(reduceMotion)) { model.drop(ids, on: row) }
            return true
        } isTargeted: {
            targeted = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(row.title), \(row.activeCount) card\(row.activeCount == 1 ? "" : "s")")
    }

    private var background: Color {
        if row.isFastLane { return Theme.accent.opacity(0.05) }
        if targeted { return Theme.accent.opacity(0.05) }
        return Color.primary.opacity(0.022)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(Theme.animation(reduceMotion)) { collapsed.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                    icon
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(row.isFastLane ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.primary))
                    count
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collapsed ? "Expand" : "Collapse") \(row.title)")
            if collapsed {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch row.kind {
        case .lane(let lane):
            Image(systemName: lane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lane == .fast ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
        case .tag(let tag):
            Circle().fill(tag.color.color).frame(width: 8, height: 8)
        case .untagged:
            Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 8, height: 8)
        case .repository, .noRepository:
            Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var count: some View {
        if row.isFastLane {
            let limit = model.settings.fastLaneLimit
            let over = row.activeCount > limit
            Text(verbatim: "\(row.activeCount) / \(limit)")
                .font(Theme.monoMedium)
                .foregroundStyle(over ? AnyShapeStyle(Theme.pending) : AnyShapeStyle(.secondary))
                .help(over ? "Over the fast lane's limit of \(limit). Keep it short so it stays fast." : "Fast lane limit: \(limit)")
            if over {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.pending)
                    .accessibilityLabel("Over the limit")
            }
        } else {
            Text(verbatim: "\(row.activeCount)")
                .font(Theme.monoMedium)
                .foregroundStyle(.secondary)
        }
    }

    private var summary: String {
        let active = row.tasks.filter { $0.column != .done }
        guard !active.isEmpty else { return "Empty" }
        let parts = columns.compactMap { column -> String? in
            let n = active.filter { $0.column == column }.count
            return n > 0 ? "\(n) \(column.title.lowercased())" : nil
        }
        return parts.joined(separator: " · ")
    }

    private var emptyHint: some View {
        let text: String =
            switch row.kind {
            case .lane(.fast): "Drag urgent cards here, or press ⌃1 on a selected card."
            case .lane(.later): "Drag cards here to park them, or press ⌃3."
            default: "Nothing here. Drag cards in to move them."
            }
        return Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// The cards of one row in one column.
private struct LaneCell: View {
    @Environment(AppModel.self) private var model
    let row: BoardRow
    let column: BoardColumn
    @State private var showOlder = false

    var body: some View {
        let tasks = row.tasks(in: column)
        // "Waiting on you" folds away cards idle for more than two days.
        let cutoff = model.now.addingTimeInterval(-48 * 3600)
        let recent = column == .waiting ? tasks.filter { $0.sortDate >= cutoff } : tasks
        let older = column == .waiting ? tasks.filter { $0.sortDate < cutoff } : []
        VStack(spacing: 8) {
            ForEach(recent) { TaskCard(task: $0) }
            if !older.isEmpty {
                Button {
                    showOlder.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .rotationEffect(.degrees(showOlder ? 90 : 0))
                        Text("Older than 2 days")
                        Text(verbatim: "\(older.count)").font(Theme.mono).foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showOlder ? "Hide \(older.count) older cards" : "Show \(older.count) older cards")
                if showOlder {
                    ForEach(older) { TaskCard(task: $0) }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 20, alignment: .top)
    }
}

// MARK: - Toolbar menus

// MARK: - Card menus
