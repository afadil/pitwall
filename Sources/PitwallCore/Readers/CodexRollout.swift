import Foundation

/// What the tail of a Codex rollout says about the thread.
public struct CodexRolloutSummary: Sendable, Hashable {
    public var turn: TurnState
    public var lastTimestamp: Date?
    public var activityTimestamps: [Date]

    public init(turn: TurnState = .unknown, lastTimestamp: Date? = nil, activityTimestamps: [Date] = []) {
        self.turn = turn
        self.lastTimestamp = lastTimestamp
        self.activityTimestamps = activityTimestamps
    }
}

/// Rules for `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`.
///
/// `event_msg` records with payload type `task_started` open a turn and
/// `task_complete` (or `turn_aborted`) close it. Verified on real rollouts.
public enum CodexRollout {
    public static func summarize(lines: [Data], activitySince: Date? = nil) -> CodexRolloutSummary {
        var summary = CodexRolloutSummary()
        var turnDecided = false
        for line in lines.reversed() {
            guard let object = JSONLine.object(line) else { continue }
            if let date = object.date("timestamp") {
                if summary.lastTimestamp.map({ date > $0 }) ?? true { summary.lastTimestamp = date }
                if let since = activitySince, date >= since { summary.activityTimestamps.append(date) }
            }
            if !turnDecided, object.string("type") == "event_msg",
                let type = object.dictionary("payload")?.string("type")
            {
                switch type {
                case "task_started":
                    summary.turn = .running
                    turnDecided = true
                case "task_complete", "turn_aborted", "task_failed":
                    summary.turn = .ended
                    turnDecided = true
                default:
                    break
                }
            }
            if activitySince == nil, turnDecided, summary.lastTimestamp != nil { break }
        }
        summary.activityTimestamps.reverse()
        return summary
    }
}
