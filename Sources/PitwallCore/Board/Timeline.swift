import Foundation

/// One block of continuous activity on the timeline.
public struct TimelineBlock: Sendable, Hashable, Identifiable {
    public var app: AgentApp
    public var taskID: String?
    public var sessionID: String
    public var interval: DateInterval

    public init(app: AgentApp, taskID: String?, sessionID: String, interval: DateInterval) {
        self.app = app
        self.taskID = taskID
        self.sessionID = sessionID
        self.interval = interval
    }

    public var id: String { "\(sessionID)@\(interval.start.timeIntervalSince1970)" }
}

public enum Timeline {
    /// Groups timestamps into spans: a gap longer than `gap` starts a new span.
    /// Spans are padded to at least `minimumLength` so single events stay visible.
    public static func cluster(
        _ timestamps: [Date],
        gap: TimeInterval = 8 * 60,
        minimumLength: TimeInterval = 3 * 60
    ) -> [DateInterval] {
        let sorted = timestamps.sorted()
        guard var start = sorted.first else { return [] }
        var end = start
        var spans: [DateInterval] = []

        func close() {
            let length = max(end.timeIntervalSince(start), minimumLength)
            spans.append(DateInterval(start: start, duration: length))
        }

        for date in sorted.dropFirst() {
            if date.timeIntervalSince(end) > gap {
                close()
                start = date
            }
            end = date
        }
        close()
        return spans
    }

    /// Blocks inside `day` for the given tasks, clipped to the day.
    public static func blocks(for tasks: [BoardTask], in day: DateInterval) -> [TimelineBlock] {
        var result: [TimelineBlock] = []
        for task in tasks {
            for session in task.sessions {
                for span in session.activity {
                    guard let clipped = span.intersection(with: day), clipped.duration > 0 else { continue }
                    result.append(TimelineBlock(app: session.app, taskID: task.id, sessionID: session.id, interval: clipped))
                }
            }
        }
        return result.sorted { $0.interval.start < $1.interval.start }
    }

    /// Overlapping or touching spans of one app merged into continuous runs,
    /// so parallel sessions draw as one block.
    public static func merged(_ blocks: [TimelineBlock], app: AgentApp, joiningGap: TimeInterval = 0) -> [DateInterval] {
        let spans = blocks.filter { $0.app == app }.map(\.interval).sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for span in spans {
            if let last = result.last, span.start.timeIntervalSince(last.end) <= joiningGap {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, span.end))
            } else {
                result.append(span)
            }
        }
        return result
    }

    /// Total active time per app, counting overlapping blocks once.
    public static func activeDuration(_ blocks: [TimelineBlock], app: AgentApp) -> TimeInterval {
        merged(blocks, app: app).reduce(0) { $0 + $1.duration }
    }

    /// The visible hour range for a day's blocks: at least `minimumHours`, ending
    /// an hour after the latest of `now` and the last block.
    public static func visibleRange(
        for blocks: [TimelineBlock],
        day: DateInterval,
        now: Date,
        calendar: Calendar = .current,
        minimumHours: Int = 8
    ) -> DateInterval {
        let earliest = blocks.map(\.interval.start).min() ?? now
        let latest = max(blocks.map(\.interval.end).max() ?? now, min(now, day.end))

        func floorHour(_ date: Date) -> Date {
            calendar.dateInterval(of: .hour, for: date)?.start ?? date
        }

        var start = floorHour(earliest)
        var end = floorHour(latest).addingTimeInterval(3600)
        let minimum = TimeInterval(minimumHours * 3600)
        if end.timeIntervalSince(start) < minimum {
            start = end.addingTimeInterval(-minimum)
        }
        start = max(start, day.start)
        end = min(max(end, start.addingTimeInterval(minimum)), day.end)
        return DateInterval(start: start, end: max(end, start))
    }
}
