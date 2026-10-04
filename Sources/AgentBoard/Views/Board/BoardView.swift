import AgentBoardCore
import SwiftUI

struct BoardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var boardFocused: Bool
    @AppStorage("doneCollapsed") private var doneCollapsed = false
    /// Row ids that are collapsed; Later starts collapsed.
    @AppStorage("collapsedRows") private var collapsedRowsRaw = "lane:later"

    private let activeColumns: [BoardColumn] = [.working, .waiting, .inReview, .ready]

    var body: some View {
        @Bindable var model = model
        let board = model.visibleBoard
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScreenHeader("Board", subtitle: subtitle(board)) {
                    BoardToolbar()
                }
                if !model.problems.isEmpty {
                    ProblemBanner(problems: model.problems)
                }
                lanes(board)
            }
            if model.inspectorOpen, let task = model.selectedTask {
                Divider().overlay(Theme.hairline)
                TaskInspector(task: task)
                    .frame(width: 320)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Theme.animation(reduceMotion), value: model.inspectorOpen)
        .focusable()
        .focused($boardFocused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(rows: 1) }
        .onKeyPress(.upArrow) { move(rows: -1) }
        .onKeyPress(.rightArrow) { move(columns: 1) }
        .onKeyPress(.leftArrow) { move(columns: -1) }
        .onKeyPress(.return) {
            guard let task = model.selectedTask else { return .ignored }
            model.openInApp(task)
            return .handled
        }
        .onKeyPress(.space) {
            guard model.selectedTask != nil else { return .ignored }
            model.inspectorOpen.toggle()
            return .handled
        }
        .onKeyPress(.escape) {
            guard model.selectedTaskID != nil || model.inspectorOpen else { return .ignored }
            model.inspectorOpen = false
            model.selectedTaskID = nil
            return .handled
        }
        .onAppear { boardFocused = true }
    }

    private func subtitle(_ board: Board) -> String {
        guard model.hasLoaded else { return "Reading sessions…" }
        let count = board.tasks.count
        var parts = ["\(count) task\(count == 1 ? "" : "s")"]
        if let updated = model.lastUpdated {
            parts.append("updated \(Format.spokenAgo(updated, now: model.now))")
        }
        return parts.joined(separator: " · ")
    }

    private var collapsedRows: Set<String> {
        Set(collapsedRowsRaw.split(separator: ",").map(String.init))
    }

    private func collapsedBinding(_ row: BoardRow) -> Binding<Bool> {
        Binding(
            get: { collapsedRows.contains(row.id) },
            set: { collapse in
                var set = collapsedRows
                if collapse { set.insert(row.id) } else { set.remove(row.id) }
                collapsedRowsRaw = set.sorted().joined(separator: ",")
            }
        )
    }

    /// Lanes cross the status columns: columns stay automatic, rows are yours.
    private func lanes(_ board: Board) -> some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 12
            // With details open, Done folds away so the active columns keep their room.
            let foldDone = doneCollapsed || model.inspectorOpen
            let doneWidth: CGFloat = foldDone ? 46 : 232
            let available = proxy.size.width - 56 - doneWidth - spacing * 4 - 20
            let columnWidth = max(model.inspectorOpen ? 206 : 236, min(350, available / 4))
            let rows = model.rows
            let counts = Dictionary(uniqueKeysWithValues: activeColumns.map { ($0, board.count($0)) })
            ScrollView([.horizontal, .vertical]) {
                HStack(alignment: .top, spacing: spacing) {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(rows) { row in
                                LaneSection(row: row, columns: activeColumns, columnWidth: columnWidth, spacing: spacing,
                                            collapsed: collapsedBinding(row))
                            }
                        } header: {
                            ColumnHeaderRow(columns: activeColumns, counts: counts, width: columnWidth, spacing: spacing,
                                            highlighted: model.highlightedColumn)
                                .padding(.vertical, 6)
                                // Blurs the cards scrolling underneath, like a native list header.
                                .background(VisualEffectBackground(material: .headerView, blending: .withinWindow, state: .active))
                        }
                    }
                    .frame(width: columnWidth * 4 + spacing * 3 + 20)
                    DoneColumnView(tasks: board.tasks(in: .done), collapsed: Binding(
                        get: { foldDone },
                        set: { doneCollapsed = $0; if !$0 { model.inspectorOpen = false } }
                    ))
                    .frame(width: doneWidth)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
        }
    }

    // MARK: Keyboard navigation

    /// Cards per column in on-screen order: row by row, skipping collapsed rows.
    private var navigableColumns: [[BoardTask]] {
        let rows = model.rows.filter { !collapsedRows.contains($0.id) }
        var grid = activeColumns.map { column in rows.flatMap { $0.tasks(in: column) } }
        if !(doneCollapsed || model.inspectorOpen) { grid.append(model.visibleBoard.tasks(in: .done)) }
        return grid
    }

    private func position() -> (Int, Int)? {
        guard let id = model.selectedTaskID else { return nil }
        for (c, tasks) in navigableColumns.enumerated() {
            if let r = tasks.firstIndex(where: { $0.id == id }) { return (c, r) }
        }
        return nil
    }

    private func move(rows: Int = 0, columns: Int = 0) -> KeyPress.Result {
        let grid = navigableColumns
        guard grid.contains(where: { !$0.isEmpty }) else { return .ignored }
        guard let (c, r) = position() else {
            model.select(grid.first { !$0.isEmpty }?.first)
            return .handled
        }
        if rows != 0 {
            let next = r + rows
            if grid[c].indices.contains(next) { model.select(grid[c][next]) }
            return .handled
        }
        var target = c + columns
        while grid.indices.contains(target), grid[target].isEmpty { target += columns }
        if grid.indices.contains(target) {
            model.select(grid[target][min(r, grid[target].count - 1)])
        }
        return .handled
    }
}

private struct BoardToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 8) {
            GroupingMenu()
            TagFilterMenu()
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("Filter", text: $model.filterText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                    .accessibilityLabel("Filter tasks")
                if !model.filterText.isEmpty {
                    Button {
                        model.filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))

            SoftIconButton(symbol: model.settings.showHidden ? "eye" : "eye.slash",
                           label: model.settings.showHidden ? "Hide hidden cards" : "Show hidden cards", size: 30) {
                model.settings.showHidden.toggle()
            }
            SoftIconButton(symbol: "arrow.clockwise", label: "Refresh  ⌘R", size: 30) {
                Task { await model.refreshAll() }
            }
            .disabled(model.isRefreshing)
            SoftIconButton(symbol: "sidebar.right", label: model.inspectorOpen ? "Hide details" : "Show details", size: 30) {
                if model.selectedTaskID == nil { model.select(model.visibleBoard.tasks.first) }
                model.inspectorOpen.toggle()
            }
        }
    }
}

struct ColumnHeader: View {
    let column: BoardColumn
    let count: Int
    var highlighted = false

    var body: some View {
        HStack(spacing: 7) {
            if column == .working, count > 0 {
                PulseDot(size: 6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: column.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(column == .waiting && count > 0 ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                    .frame(width: 14, height: 14)
            }
            Text(column.title)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(Theme.monoMedium)
                .foregroundStyle(column == .waiting && count > 0 ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent.opacity(highlighted ? 0.14 : 0))
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyColumn: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
    }
}

/// Done: a compact list that can fold into a slim strip.
struct DoneColumnView: View {
    @Environment(AppModel.self) private var model
    let tasks: [BoardTask]
    @Binding var collapsed: Bool

    var body: some View {
        if collapsed {
            Button {
                collapsed = false
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: BoardColumn.done.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text("\(tasks.count)")
                        .font(Theme.monoMedium)
                        .foregroundStyle(.secondary)
                    Text("Done")
                        .font(.caption.weight(.semibold))
                        .fixedSize()
                        .rotationEffect(.degrees(90))
                        .frame(width: 20, height: 44)
                    Spacer()
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show done")
            .accessibilityLabel("Done, \(tasks.count) tasks, collapsed. Expand")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ColumnHeader(column: .done, count: tasks.count)
                    Button {
                        collapsed = true
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse done")
                    .accessibilityLabel("Collapse done")
                }
                ScrollView(.vertical) {
                    VStack(spacing: 2) {
                        if tasks.isEmpty {
                            EmptyColumn(message: BoardColumn.done.emptyMessage)
                        }
                        ForEach(tasks) { task in
                            DoneRow(task: task)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Done, \(tasks.count) tasks")
        }
    }
}

private struct DoneRow: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    @State private var hovered = false

    var body: some View {
        let selected = model.selectedTaskID == task.id
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: task.pullRequest?.stateSymbol ?? "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(task.pullRequest?.stateColor ?? .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                Text(task.pullRequest.map { "#\($0.number) · \(task.repo?.name ?? "")" } ?? task.locationLine)
                    .font(Theme.monoSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(Format.ago(task.pullRequest?.finishedAt ?? task.lastActivity, now: model.now))
                .font(Theme.monoSmall)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.14) : Color.primary.opacity(hovered ? 0.05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .gesture(TapGesture(count: 2).onEnded { model.openInApp(task) })
        .simultaneousGesture(TapGesture().onEnded {
            model.select(task)
            model.inspectorOpen = true
        })
        .contextMenu { TaskActionsMenu(task: task) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TaskCard.accessibilityDescription(task, now: model.now))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.select(task); model.inspectorOpen = true }
        .accessibilityActions { TaskAccessibilityActions(task: task) }
    }
}
