import AgentBoardCore
import SwiftUI

/// Today's activity as rounded blocks on an hour axis: orange for Claude and
/// white (black in light mode) for Codex, like the pads in the sequencer reference.
struct ActivityTimeline: View {
    enum Style { case full, compact }

    let blocks: [TimelineBlock]
    let now: Date
    var style: Style = .full
    @Environment(\.calendar) private var calendar

    private var range: DateInterval {
        let day = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86400)
        return Timeline.visibleRange(for: blocks, day: day, now: now, calendar: calendar, minimumHours: style == .full ? 10 : 8)
    }

    var body: some View {
        let range = range
        VStack(alignment: .leading, spacing: style == .full ? 10 : 6) {
            if style == .full {
                ForEach(AgentApp.allCases, id: \.self) { app in
                    HStack(spacing: 12) {
                        Text(app.displayName)
                            .font(Theme.monoSmall)
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .leading)
                        track(blocks.filter { $0.app == app }, range: range, height: 30)
                    }
                }
                HStack(spacing: 12) {
                    Color.clear.frame(width: 46, height: 1)
                    axis(range)
                }
            } else {
                // Like the reference: a main row of blocks and a thin row beneath.
                track(blocks.filter { $0.app == .claude }, range: range, height: 28)
                thinLane(blocks.filter { $0.app == .codex }, range: range)
                axis(range)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func track(_ items: [TimelineBlock], range: DateInterval, height: CGFloat) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                // Hour grid.
                ForEach(hours(in: range), id: \.self) { hour in
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 0.5)
                        .offset(x: x(hour, range: range, width: width))
                }
                ForEach(items) { block in
                    let start = x(block.interval.start, range: range, width: width)
                    let end = x(block.interval.end, range: range, width: width)
                    Pad(color: block.app.tint)
                        .frame(width: max(6, end - start), height: height)
                        .offset(x: start)
                }
                if range.contains(now) {
                    NowMarker(height: height + 6)
                        .offset(x: x(now, range: range, width: width) - 3, y: 0)
                }
            }
        }
        .frame(height: height)
    }

    private func thinLane(_ items: [TimelineBlock], range: DateInterval) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.05))
                ForEach(items) { block in
                    let start = x(block.interval.start, range: range, width: width)
                    let end = x(block.interval.end, range: range, width: width)
                    Capsule()
                        .fill(block.app.tint)
                        .frame(width: max(6, end - start))
                        .offset(x: start)
                }
            }
        }
        .frame(height: 6)
    }

    private func axis(_ range: DateInterval) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let marks = hours(in: range).filter { calendar.component(.hour, from: $0) % (style == .full ? 2 : 3) == 0 }
            ZStack(alignment: .leading) {
                ForEach(marks, id: \.self) { hour in
                    Text(hour.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .offset(x: x(hour, range: range, width: width) - 6)
                }
            }
        }
        .frame(height: 12)
    }

    private func hours(in range: DateInterval) -> [Date] {
        var result: [Date] = []
        var hour = calendar.dateInterval(of: .hour, for: range.start)?.start ?? range.start
        if hour < range.start { hour = hour.addingTimeInterval(3600) }
        while hour <= range.end {
            result.append(hour)
            hour = hour.addingTimeInterval(3600)
        }
        return result
    }

    private func x(_ date: Date, range: DateInterval, width: CGFloat) -> CGFloat {
        guard range.duration > 0 else { return 0 }
        let fraction = min(1, max(0, date.timeIntervalSince(range.start) / range.duration))
        return fraction * width
    }

    private var accessibilitySummary: String {
        let parts = AgentApp.allCases.map { app -> String in
            let count = blocks.filter { $0.app == app }.count
            let duration = Format.duration(Timeline.activeDuration(blocks, app: app))
            return "\(app.displayName) active \(duration) in \(count) block\(count == 1 ? "" : "s")"
        }
        return "Today's activity. " + parts.joined(separator: ". ")
    }
}

/// A soft, slightly raised block.
private struct Pad: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(color.gradient)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.25), radius: 3, y: 1)
            .padding(.vertical, 4)
    }
}

private struct NowMarker: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Rectangle().fill(Theme.accent).frame(width: 1.5)
        }
        .frame(width: 6, height: height)
        .offset(y: -3)
    }
}
