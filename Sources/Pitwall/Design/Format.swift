import PitwallCore
import AppKit
import SwiftUI

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

    /// "Updated just now", "Updated 4m ago".
    static func updated(_ date: Date, now: Date) -> String {
        let ago = ago(date, now: now)
        return ago == "now" ? "Updated just now" : "Updated \(ago) ago"
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
