import Foundation

/// What the tail of a Claude transcript says about the session.
public struct ClaudeTranscriptSummary: Sendable, Hashable {
    public var branch: String?
    public var lastTimestamp: Date?
    public var turn: TurnState
    public var activityTimestamps: [Date]

    public init(branch: String? = nil, lastTimestamp: Date? = nil, turn: TurnState = .unknown, activityTimestamps: [Date] = []) {
        self.branch = branch
        self.lastTimestamp = lastTimestamp
        self.turn = turn
        self.activityTimestamps = activityTimestamps
    }
}

/// Rules for reading `~/.claude/projects/<encoded cwd>/<cliSessionId>.jsonl`.
///
/// Verified against real transcripts (2026-10-04): a finished turn ends with a
/// `system` line whose `subtype` is `stop_hook_summary` (it carries `stopReason`),
/// usually right after an assistant message with `stop_reason: end_turn`.
/// Bookkeeping lines (`last-prompt`, `custom-title`, `mode`, `cost-state`, …) can
/// follow and are ignored. A turn in progress ends with a user prompt, a tool
/// result, or an assistant `tool_use`.
public enum ClaudeTranscript {
    public static func summarize(lines: [Data], activitySince: Date? = nil) -> ClaudeTranscriptSummary {
        var summary = ClaudeTranscriptSummary()
        var turnDecided = false

        for line in lines.reversed() {
            guard let object = JSONLine.object(line) else { continue }

            if let date = object.date("timestamp") {
                if summary.lastTimestamp.map({ date > $0 }) ?? true {
                    summary.lastTimestamp = date
                }
                if let since = activitySince, date >= since {
                    summary.activityTimestamps.append(date)
                }
            }

            if summary.branch == nil, let branch = object.string("gitBranch"), branch != "HEAD" {
                summary.branch = branch
            }

            if !turnDecided, let state = turnState(of: object) {
                summary.turn = state
                turnDecided = true
            }

            // Without an activity window we can stop once both answers are known.
            if activitySince == nil, turnDecided, summary.branch != nil, summary.lastTimestamp != nil {
                break
            }
        }
        summary.activityTimestamps.reverse()
        return summary
    }

    /// The turn state a single line implies, or nil when the line says nothing about it.
    static func turnState(of object: [String: Any]) -> TurnState? {
        if object.bool("isSidechain") == true { return nil }
        guard let type = object.string("type") else { return nil }

        switch type {
        case "system":
            switch object.string("subtype") {
            case "stop_hook_summary", "turn_duration": return .ended
            case "api_error": return .running
            default: return nil
            }

        case "assistant":
            let message = object.dictionary("message")
            switch message?.string("stop_reason") {
            case "end_turn", "stop_sequence", "max_tokens", "refusal": return .ended
            case "tool_use", "pause_turn", nil: return .running
            default: return .ended
            }

        case "user":
            if object.bool("isMeta") == true { return nil }
            let message = object.dictionary("message")
            let content = message?["content"]
            let texts: [String]
            var hasToolResult = false
            switch content {
            case let string as String:
                texts = [string]
            case let blocks as [[String: Any]]:
                texts = blocks.compactMap { $0["text"] as? String }
                hasToolResult = blocks.contains { $0.string("type") == "tool_result" }
            default:
                texts = []
            }
            if texts.contains(where: { $0.hasPrefix("[Request interrupted by user") }) {
                return .ended
            }
            if !hasToolResult, texts.contains(where: { $0.hasPrefix("<local-command") || $0.hasPrefix("<command-name>") }) {
                return nil
            }
            return .running

        default:
            return nil
        }
    }

    /// Folder name Claude uses under `~/.claude/projects` for a working directory:
    /// every character other than ASCII letters and digits becomes `-`.
    public static func encodeProjectDirectory(_ cwd: String) -> String {
        String(cwd.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            let isAlnum = (v >= 48 && v <= 57) || (v >= 65 && v <= 90) || (v >= 97 && v <= 122)
            return isAlnum ? Character(scalar) : "-"
        })
    }
}
