import PitwallCore
import AppKit
import SwiftUI

/// Design tokens. One warm accent; semantic colours only for CI and review state.
enum Theme {
    // MARK: Colour

    /// Warm orange accent, a touch deeper in light mode for contrast.
    static let accent = Color(light: NSColor(srgbRed: 0.91, green: 0.38, blue: 0.13, alpha: 1),
                              dark: NSColor(srgbRed: 1.00, green: 0.47, blue: 0.22, alpha: 1))
    /// Accent for text on light backgrounds (meets 4.5:1 on white).
    static let accentText = Color(light: NSColor(srgbRed: 0.72, green: 0.27, blue: 0.05, alpha: 1),
                                  dark: NSColor(srgbRed: 1.00, green: 0.56, blue: 0.33, alpha: 1))

    static let success = Color(nsColor: .systemGreen)
    static let failure = Color(nsColor: .systemRed)
    /// Amber; darker in light mode so "CI running" text stays readable on white.
    static let pending = Color(light: NSColor(srgbRed: 0.70, green: 0.47, blue: 0.0, alpha: 1), dark: .systemYellow)
    static let merged = Color(nsColor: .systemPurple)

    /// The Codex mark colour on the timeline: near-white in dark, near-black in light.
    static let codex = Color(light: NSColor(white: 0.16, alpha: 1), dark: NSColor(white: 0.93, alpha: 1))

    static let hairline = Color(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.09))
    static let strongHairline = Color(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.14))

    /// Raised surface for cards on the content panel.
    static func cardFill(hovered: Bool = false, reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return Color(light: NSColor(white: hovered ? 0.95 : 0.97, alpha: 1),
                         dark: NSColor(white: hovered ? 0.20 : 0.17, alpha: 1))
        }
        return Color(light: NSColor(white: 1, alpha: hovered ? 0.95 : 0.78),
                     dark: NSColor(white: 1, alpha: hovered ? 0.085 : 0.055))
    }

    /// The inset content panel that sits on the window material.
    static func panelFill(reduceTransparency: Bool) -> Color {
        if reduceTransparency {
            return Color(light: NSColor(white: 0.985, alpha: 1), dark: NSColor(white: 0.115, alpha: 1))
        }
        return Color(light: NSColor(white: 0.99, alpha: 0.72), dark: NSColor(srgbRed: 0.07, green: 0.065, blue: 0.06, alpha: 0.72))
    }

    // MARK: Shape

    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let controlRadius: CGFloat = 9

    // MARK: Type

    /// Small monospaced label (branches, counts, timestamps).
    static let mono = Font.system(.caption, design: .monospaced)
    static let monoSmall = Font.system(.caption2, design: .monospaced)
    static let monoMedium = Font.system(.caption, design: .monospaced).weight(.medium)
    static let largeTitle = Font.system(size: 28, weight: .semibold)
    static let sectionLabel = Font.system(.caption, design: .monospaced)

    // MARK: Motion

    static func animation(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28)
    }
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil ? dark : light
        })
    }
}

// MARK: - Semantics

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

// MARK: - Formatting

enum Format {
    /// "now", "4m", "3h", "2d".
    static func ago(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45: return "now"
        case ..<3600: return "\(Int((seconds / 60).rounded()))m"
        case ..<(48 * 3600): return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86400))d"
        }
    }

    /// Spoken form for VoiceOver: "4 minutes ago".
    static func spokenAgo(_ date: Date?, now: Date) -> String {
        guard let date else { return "unknown time" }
        if now.timeIntervalSince(date) < 45 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// Clock time today, weekday this week, short date before that.
    static func shortWhen(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date) }
        if now.timeIntervalSince(date) < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// `/Users/me/work/x` → `~/work/x`.
    static func path(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
