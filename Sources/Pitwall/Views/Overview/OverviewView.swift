import PitwallCore
import SwiftUI

/// Stat cards, today's activity per app, and recent pull requests.
struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader("Overview", subtitle: model.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                if !model.problems.isEmpty {
                    ProblemBanner(problems: model.problems)
                }
                VStack(alignment: .leading, spacing: 30) {
                    statCards
                    todaySection
                    pullRequestsSection
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .scrollIndicators(.automatic)
    }

    private var statCards: some View {
        HStack(spacing: 12) {
            ForEach([BoardColumn.working, .waiting, .inReview, .ready]) { column in
                StatCard(column: column, count: model.board.count(column)) {
                    model.screen = .board
                    model.highlightedColumn = column
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        if model.highlightedColumn == column { model.highlightedColumn = nil }
                    }
                }
            }
        }
    }

    private var todaySection: some View {
        let blocks = model.timelineBlocks()
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Today") {
                HStack(spacing: 14) {
                    ForEach(AgentApp.allCases, id: \.self) { app in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(app.tint).frame(width: 10, height: 10)
                            Text("\(app.displayName) \(Format.duration(Timeline.activeDuration(blocks, app: app)))")
                                .font(Theme.monoSmall)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            ActivityTimeline(blocks: blocks, now: model.now, style: .full)
                .padding(16)
                .surface(radius: 14)
        }
    }

    private var pullRequestsSection: some View {
        let recent = model.board.tasks
            .filter { $0.pullRequest != nil }
            .sorted { ($0.pullRequest?.updatedAt ?? .distantPast) > ($1.pullRequest?.updatedAt ?? .distantPast) }
            .prefix(8)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Pull requests")
            if recent.isEmpty {
                Text(
                    model.github.fetchedAt == nil
                        ? "Pull requests appear once gh has been asked." : "No pull requests linked to your sessions yet."
                )
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, task in
                        if index > 0 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                        PullRequestRow(task: task)
                    }
                }
                .surface(radius: 14)
            }
        }
    }
}

/// Big numeral, symbol and label, like the overview reference's stat cards.
struct StatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let column: BoardColumn
    let count: Int
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(count)")
                        .font(.system(size: 40, weight: .medium).monospacedDigit())
                        .foregroundStyle(
                            count > 0 && (column == .working || column == .waiting)
                                ? AnyShapeStyle(Theme.accentText) : AnyShapeStyle(.primary)
                        )
                        .contentTransition(.numericText(value: Double(count)))
                    Spacer()
                    if column == .working, count > 0 {
                        PulseDot(size: 6)
                    }
                }
                Spacer(minLength: 18)
                Image(systemName: column.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                Text(column.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
            .surface(radius: 16, hovered: hovered)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(reduceMotion ? nil : .snappy, value: count)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Show on the board")
        .accessibilityLabel("\(column.title): \(count)")
        .accessibilityHint("Shows the board")
    }
}

private struct PullRequestRow: View {
    @Environment(AppModel.self) private var model
    let task: BoardTask
    @State private var hovered = false

    var body: some View {
        if let pr = task.pullRequest {
            Button {
                model.openPullRequest(task)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: pr.stateSymbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pr.stateColor)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(pr.stateColor.opacity(0.13)))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(verbatim: "#\(pr.number)").font(Theme.monoMedium).foregroundStyle(.secondary)
                            Text(pr.title).font(.callout).lineLimit(1)
                        }
                        Text(detail(pr))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    ForEach(task.apps, id: \.self) { AppBadge(app: $0, compact: true) }
                    Text(Format.ago(pr.updatedAt, now: model.now))
                        .font(Theme.monoSmall)
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(hovered ? 0.04 : 0))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .contextMenu { TaskActionsMenu(task: task) }
            .accessibilityLabel("Pull request \(pr.number), \(pr.title), \(detail(pr))")
            .accessibilityHint("Opens on GitHub")
        }
    }

    private func detail(_ pr: PullRequest) -> String {
        var parts = [pr.repo, pr.headRefName, pr.stateLabel]
        if pr.state == .open {
            parts.append(pr.checks.state.label)
            if let review = pr.reviewDecision.label { parts.append(review) }
        }
        return parts.joined(separator: " · ")
    }
}
