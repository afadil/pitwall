import Foundation

/// Column rules from SPEC.md, in one place.
public enum BoardRules {
    /// A running turn with no writes for this long is treated as stalled
    /// (usually a permission prompt waiting on you, or an app that quit mid-turn).
    public static let stalledAfter: TimeInterval = 10 * 60
    /// When the tail can't tell, recent activity counts as working.
    public static let recentActivityWindow: TimeInterval = 3 * 60
    /// Merged or closed PRs stay in Done this long.
    public static let doneWindow: TimeInterval = 7 * 24 * 3600

    public static func isWorking(_ session: AgentSession, now: Date) -> Bool {
        let lastSeen = [session.lastWrite, session.lastActivity].compactMap { $0 }.max()
        guard let lastSeen else { return false }
        let idle = now.timeIntervalSince(lastSeen)
        switch session.turn {
        case .running: return idle < stalledAfter
        case .unknown: return idle < recentActivityWindow
        case .ended: return false
        }
    }

    /// Column for a task, or nil when it should not be on the board at all
    /// (its PR finished more than a week ago).
    public static func placement(
        sessions: [AgentSession],
        pullRequest: PullRequest?,
        now: Date
    ) -> (column: BoardColumn, reason: ReviewReason?)? {
        if sessions.contains(where: { isWorking($0, now: now) }) {
            return (.working, nil)
        }
        guard let pr = pullRequest else {
            return (.waiting, nil)
        }
        switch pr.state {
        case .merged, .closed:
            guard let finished = pr.finishedAt, now.timeIntervalSince(finished) <= doneWindow else { return nil }
            return (.done, nil)
        case .open:
            if pr.isDraft { return (.inReview, .draft) }
            switch pr.checks.state {
            case .failing: return (.inReview, .ciFailing)
            case .pending: return (.inReview, pr.reviewDecision == .changesRequested ? .changesRequested : .ciRunning)
            case .passing, .none: break
            }
            switch pr.reviewDecision {
            case .changesRequested: return (.inReview, .changesRequested)
            case .reviewRequired: return (.inReview, .awaitingReview)
            case .approved, .none: return (.ready, nil)
            }
        }
    }
}
