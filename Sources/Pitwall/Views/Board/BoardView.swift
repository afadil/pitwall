import PitwallCore
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
                                LaneSection(
                                    row: row, columns: activeColumns, columnWidth: columnWidth, spacing: spacing,
                                    collapsed: collapsedBinding(row))
                            }
                        } header: {
                            ColumnHeaderRow(
                                columns: activeColumns, counts: counts, width: columnWidth, spacing: spacing,
                                highlighted: model.highlightedColumn
                            )
                            .padding(.vertical, 6)
                            // Blurs the cards scrolling underneath, like a native list header.
                            .background(VisualEffectBackground(material: .headerView, blending: .withinWindow, state: .active))
                        }
                    }
                    .frame(width: columnWidth * 4 + spacing * 3 + 20)
                    DoneColumnView(
                        tasks: board.tasks(in: .done),
                        collapsed: Binding(
                            get: { foldDone },
                            set: {
                                doneCollapsed = $0
                                if !$0 { model.inspectorOpen = false }
                            }
                        )
                    )
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
