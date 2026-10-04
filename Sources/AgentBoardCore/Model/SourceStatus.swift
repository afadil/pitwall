import Foundation

/// Read status of one data source, shown in Settings and in board banners.
public struct SourceStatus: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case claudeSessions
        case claudeTranscripts
        case codexThreads
        case codexRollouts
        case github
    }

    public enum Health: Sendable, Hashable {
        case ok
        /// Readable, but some items could not be parsed.
        case warning
        /// Not there at all (app not installed or never used).
        case missing
        /// There, but unreadable: the format probably changed.
        case error
    }

    public var kind: Kind
    public var path: String
    public var health: Health
    public var detail: String

    public init(kind: Kind, path: String, health: Health, detail: String) {
        self.kind = kind
        self.path = path
        self.health = health
        self.detail = detail
    }

    public var id: Kind { kind }

    public var title: String {
        switch kind {
        case .claudeSessions: "Claude sessions"
        case .claudeTranscripts: "Claude transcripts"
        case .codexThreads: "Codex threads"
        case .codexRollouts: "Codex rollouts"
        case .github: "GitHub CLI"
        }
    }
}

/// Items read from a source plus how the read went.
public struct SourceRead<Item: Sendable>: Sendable {
    public var items: [Item]
    public var statuses: [SourceStatus]

    public init(items: [Item], statuses: [SourceStatus]) {
        self.items = items
        self.statuses = statuses
    }
}
