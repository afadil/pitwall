import PitwallCore
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            Text("Pitwall")
                .font(.callout.weight(.semibold))
            Spacer()
            if let updated = model.lastUpdated {
                Text(Format.updated(updated, now: model.now))
                    .font(Theme.monoSmall)
                    .foregroundStyle(.tertiary)
            }
            Button {
                Task { await model.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(model.isRefreshing && !reduceMotion ? 180 : 0))
                    .opacity(model.isRefreshing && reduceMotion ? 0.4 : 1)
                    .animation(
                        model.isRefreshing && !reduceMotion ? .linear(duration: 0.6).repeatForever(autoreverses: false) : .default,
                        value: model.isRefreshing)
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
                        .fixedSize()
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
        // Fast-lane cards come first.
        let tasks = AppModel.fastFirst(model.board.tasks(in: segment.column))
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
                            PanelRow(task: task, showOnBoard: { openBoard(selecting: task) })
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
