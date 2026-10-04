import AgentBoardCore
import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .orange: Color(nsColor: .systemOrange)
        case .red: Color(nsColor: .systemRed)
        case .pink: Color(nsColor: .systemPink)
        case .purple: Color(nsColor: .systemPurple)
        case .blue: Color(nsColor: .systemBlue)
        case .teal: Color(nsColor: .systemTeal)
        case .green: Color(nsColor: .systemGreen)
        case .gray: Color(nsColor: .systemGray)
        }
    }

    var title: String { rawValue.capitalized }
}

extension Lane {
    var symbol: String {
        switch self {
        case .fast: "bolt.fill"
        case .normal: "rectangle.split.3x1"
        case .later: "tray"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .fast: "1"
        case .normal: "2"
        case .later: "3"
        }
    }
}

/// Your tag: coloured dot and name.
struct TagChip: View {
    let tag: CardTag
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tag.color.color).frame(width: 6, height: 6)
            Text(tag.name)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove tag \(tag.name)")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tag.color.color.opacity(0.10)))
        .overlay(Capsule().strokeBorder(tag.color.color.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: onRemove == nil ? .ignore : .contain)
        .accessibilityLabel("Tag \(tag.name)")
    }
}

/// A GitHub label: ring instead of a dot, so it reads as coming from GitHub.
struct LabelChip: View {
    let label: PRLabel

    var body: some View {
        HStack(spacing: 4) {
            Circle().strokeBorder(Self.color(label.color), lineWidth: 1.5).frame(width: 7, height: 7)
            Text(label.name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("GitHub label \(label.name)")
    }

    static func color(_ hex: String?) -> Color {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return .secondary }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

/// Tags and labels on a card: up to three chips, then "+N".
struct CardTagsRow: View {
    let task: BoardTask

    var body: some View {
        let tags = task.tags
        let labels = task.labels
        let shown = 3
        HStack(spacing: 4) {
            ForEach(tags.prefix(shown)) { TagChip(tag: $0) }
            ForEach(labels.prefix(max(0, shown - tags.count)), id: \.name) { LabelChip(label: $0) }
            let extra = tags.count + labels.count - shown
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
                    .help((tags.dropFirst(shown).map(\.name) + labels.map(\.name)).joined(separator: ", "))
            }
        }
        .lineLimit(1)
    }
}

/// Column titles above the lanes, aligned with the lane cells.
struct ColumnHeaderRow: View {
    let columns: [BoardColumn]
    let counts: [BoardColumn: Int]
    let width: CGFloat
    let spacing: CGFloat
    var highlighted: BoardColumn?

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(columns) { column in
                ColumnHeader(column: column, count: counts[column] ?? 0, highlighted: highlighted == column)
                    .frame(width: width)
            }
        }
        .padding(.horizontal, 10)
    }
}

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
                .strokeBorder(targeted ? Theme.accent : (row.isFastLane ? Theme.accent.opacity(0.22) : .clear),
                              style: StrokeStyle(lineWidth: targeted ? 1.5 : 0.5, dash: targeted ? [5, 4] : []))
        )
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { ids, _ in
            withAnimation(Theme.animation(reduceMotion)) { model.drop(ids, on: row) }
            return true
        } isTargeted: { targeted = $0 }
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
        case let .lane(lane):
            Image(systemName: lane.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(lane == .fast ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
        case let .tag(tag):
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
        let text: String = switch row.kind {
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

struct GroupingMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            Picker("Group by", selection: $model.settings.grouping) {
                ForEach(Grouping.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            ToolbarMenuLabel(symbol: "rectangle.grid.1x2", text: "By \(model.settings.grouping.title.lowercased())", active: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Group rows by lane, tag or repository")
        .accessibilityLabel("Group by \(model.settings.grouping.title)")
    }
}

struct TagFilterMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let labels = BoardLayout.labels(in: model.board.tasks)
        Menu {
            if model.organization.tags.isEmpty && labels.isEmpty {
                Text("No tags yet. Right-click a card to add one.")
            }
            if !model.organization.tags.isEmpty {
                Section("Your tags") {
                    ForEach(model.organization.tags) { tag in
                        Toggle(isOn: Binding(get: { model.tagFilter.tagIDs.contains(tag.id) },
                                             set: { _ in model.tagFilter.toggle(tag: tag.id) })) {
                            Label { Text(tag.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(tag.color.color) }
                        }
                    }
                }
            }
            if !labels.isEmpty {
                Section("GitHub labels") {
                    ForEach(labels, id: \.name) { label in
                        Toggle(label.name, isOn: Binding(get: { model.tagFilter.labels.contains(label.name.lowercased()) },
                                                         set: { _ in model.tagFilter.toggle(label: label.name) }))
                    }
                }
            }
            Divider()
            Picker("Match", selection: $model.tagFilter.mode) {
                Text("Any selected tag").tag(TagFilter.Mode.any)
                Text("All selected tags").tag(TagFilter.Mode.all)
            }
            .pickerStyle(.inline)
            if model.tagFilter.isActive {
                Button("Clear tag filter") { model.tagFilter = TagFilter(mode: model.tagFilter.mode) }
            }
        } label: {
            ToolbarMenuLabel(symbol: "tag", text: model.tagFilter.isActive ? "\(model.tagFilter.count)" : "Tags",
                             active: model.tagFilter.isActive)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Filter by tags and GitHub labels")
        .accessibilityLabel(model.tagFilter.isActive ? "Tag filter, \(model.tagFilter.count) selected" : "Filter by tag")
    }
}

/// Soft capsule label for toolbar menus, matching the other toolbar controls.
struct ToolbarMenuLabel: View {
    let symbol: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption.weight(.semibold))
            Text(text).font(.callout)
        }
        .foregroundStyle(active ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .fill(active ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }
}

// MARK: - Card menus

/// "Lane" and "Tags" submenus for a card's context menu.
struct OrganizeMenu: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask

    var body: some View {
        Menu("Lane", systemImage: "rectangle.grid.1x2") {
            Picker("Lane", selection: Binding(get: { task.lane }, set: { model.setLane($0, for: task) })) {
                ForEach(Lane.allCases) { lane in
                    Label(lane.title, systemImage: lane.symbol).tag(lane)
                }
            }
            .pickerStyle(.inline)
        }
        Menu("Tags", systemImage: "tag") {
            ForEach(model.organization.tags) { tag in
                Toggle(isOn: Binding(get: { model.hasTag(tag, task) }, set: { model.setTag(tag, on: $0, for: task) })) {
                    Label { Text(tag.name) } icon: { Image(systemName: "circle.fill").foregroundStyle(tag.color.color) }
                }
            }
            if !model.organization.tags.isEmpty { Divider() }
            Button("New tag…") { model.beginNewTag(for: task) }
        }
    }
}

/// Names a new tag, then adds it to the card it was started from.
struct NewTagAlert: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    func body(content: Content) -> some View {
        @Bindable var model = model
        content.alert("New tag", isPresented: $model.isNamingNewTag) {
            TextField("Name", text: $name)
            Button("Add") {
                model.createTag(named: name, for: model.newTagTarget)
                name = ""
                model.newTagTarget = nil
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                name = ""
                model.newTagTarget = nil
            }
        } message: {
            if let task = model.newTagTarget {
                Text("Adds the tag to “\(task.title)”.")
            }
        }
    }
}
