import AppKit
import PitwallCore
import SwiftUI

extension CIState {
    var label: String {
        switch self {
        case .none: "No checks"
        case .pending: "CI running"
        case .passing: "CI passing"
        case .failing: "CI failing"
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .pending: "circle.dotted.circle"
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none: .secondary
        case .pending: Theme.pending
        case .passing: Theme.success
        case .failing: Theme.failure
        }
    }
}

extension ReviewDecision {
    var label: String? {
        switch self {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Review required"
        case .none: nil
        }
    }

    var symbol: String {
        switch self {
        case .approved: "checkmark.seal.fill"
        case .changesRequested: "exclamationmark.bubble.fill"
        case .reviewRequired: "eye"
        case .none: "minus"
        }
    }

    var color: Color {
        switch self {
        case .approved: Theme.success
        case .changesRequested: Theme.failure
        case .reviewRequired, .none: .secondary
        }
    }
}

extension PullRequest {
    var stateLabel: String {
        switch state {
        case .open: isDraft ? "Draft" : "Open"
        case .merged: "Merged"
        case .closed: "Closed"
        }
    }

    var stateSymbol: String {
        switch state {
        case .open: isDraft ? "circle.dashed" : "arrow.trianglehead.pull"
        case .merged: "arrow.trianglehead.merge"
        case .closed: "xmark.circle"
        }
    }

    var stateColor: Color {
        switch state {
        case .open: isDraft ? .secondary : Theme.success
        case .merged: Theme.merged
        case .closed: .secondary
        }
    }
}

extension ReviewReason {
    var color: Color {
        switch self {
        case .draft, .awaitingReview, .stacked: .secondary
        case .ciFailing, .changesRequested: Theme.failure
        case .ciRunning: Theme.pending
        }
    }

    var symbol: String {
        switch self {
        case .draft: "circle.dashed"
        case .ciFailing: "xmark.circle.fill"
        case .changesRequested: "exclamationmark.bubble.fill"
        case .ciRunning: "circle.dotted.circle"
        case .awaitingReview: "eye"
        case .stacked: "square.stack.3d.up"
        }
    }
}

extension BoardColumn {
    var symbol: String {
        switch self {
        case .working: "bolt.fill"
        case .waiting: "hand.raised.fill"
        case .inReview: "eye.fill"
        case .ready: "arrow.trianglehead.merge"
        case .done: "checkmark.circle.fill"
        }
    }

    var emptyMessage: String {
        switch self {
        case .working: "No agent is working right now"
        case .waiting: "Nothing is waiting on you"
        case .inReview: "No pull requests in review"
        case .ready: "Nothing is ready to merge"
        case .done: "Nothing merged this week"
        }
    }
}

extension AgentApp {
    /// Timeline and badge colour: Claude takes the accent, Codex the neutral mark.
    var tint: Color {
        switch self {
        case .claude: Theme.accent
        case .codex: Theme.codex
        }
    }
}

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
