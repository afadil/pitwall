import Foundation

/// What the board's rows are. The fast lane stays on top and Later at the bottom
/// in every grouping; the grouping decides the rows in between.
public enum Grouping: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case lane
    case tag
    case repository

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lane: "Lane"
        case .tag: "Tag"
        case .repository: "Repository"
        }
    }
}

/// Filter by your tags and GitHub labels.
public struct TagFilter: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable, Hashable {
        /// Cards with at least one selected tag.
        case any
        /// Cards with every selected tag.
        case all
    }

    public var tagIDs: Set<UUID>
    /// Lowercased GitHub label names.
    public var labels: Set<String>
    public var mode: Mode

    public init(tagIDs: Set<UUID> = [], labels: Set<String> = [], mode: Mode = .any) {
        self.tagIDs = tagIDs
        self.labels = Set(labels.map { $0.lowercased() })
        self.mode = mode
    }

    public var isActive: Bool { !tagIDs.isEmpty || !labels.isEmpty }
    public var count: Int { tagIDs.count + labels.count }

    public func matches(_ task: BoardTask) -> Bool {
        guard isActive else { return true }
        let tags = Set(task.tags.map(\.id))
        let labelNames = Set(task.labels.map { $0.name.lowercased() })
        switch mode {
        case .any: return !tags.isDisjoint(with: tagIDs) || !labelNames.isDisjoint(with: labels)
        case .all: return tagIDs.isSubset(of: tags) && labels.isSubset(of: labelNames)
        }
    }

    public mutating func toggle(tag id: UUID) {
        if tagIDs.contains(id) { tagIDs.remove(id) } else { tagIDs.insert(id) }
    }

    public mutating func toggle(label name: String) {
        let key = name.lowercased()
        if labels.contains(key) { labels.remove(key) } else { labels.insert(key) }
    }
}

/// One horizontal band of the board.
public struct BoardRow: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case lane(Lane)
        case tag(CardTag)
        case untagged
        case repository(RepoID)
        case noRepository
    }

    public var kind: Kind
    public var tasks: [BoardTask]

    public var id: String {
        switch kind {
        case .lane(let lane): "lane:\(lane.rawValue)"
        case .tag(let tag): "tag:\(tag.id.uuidString)"
        case .untagged: "untagged"
        case .repository(let repo): "repo:\(repo.key)"
        case .noRepository: "no-repo"
        }
    }

    public var title: String {
        switch kind {
        case .lane(let lane): lane.title
        case .tag(let tag): tag.name
        case .untagged: "No tag"
        case .repository(let repo): repo.displayName
        case .noRepository: "No repository"
        }
    }

    /// The lane a card moves to when dropped here.
    public var dropLane: Lane {
        if case .lane(let lane) = kind { return lane }
        return .normal
    }

    /// The tag a card gains when dropped here.
    public var dropTag: UUID? {
        if case .tag(let tag) = kind { return tag.id }
        return nil
    }

    public var isFastLane: Bool { kind == .lane(.fast) }
    public var isLater: Bool { kind == .lane(.later) }

    /// Cards still in play (Done doesn't count toward the fast-lane limit).
    public var activeCount: Int { tasks.reduce(0) { $0 + ($1.column == .done ? 0 : 1) } }

    public func tasks(in column: BoardColumn) -> [BoardTask] {
        tasks.filter { $0.column == column }
    }
}

public enum BoardLayout {
    /// Rows for the board. Fast lane and Later are always present (they're drop
    /// targets even when empty); grouped rows appear only when they have cards.
    public static func rows(_ tasks: [BoardTask], grouping: Grouping, tags: [CardTag]) -> [BoardRow] {
        let fast = tasks.filter { $0.lane == .fast }
        let later = tasks.filter { $0.lane == .later }
        let middle = tasks.filter { $0.lane == .normal }

        var rows = [BoardRow(kind: .lane(.fast), tasks: fast)]
        switch grouping {
        case .lane:
            rows.append(BoardRow(kind: .lane(.normal), tasks: middle))
        case .tag:
            // A card with several tags sits under the first of them in tag-list order.
            var byTag: [UUID: [BoardTask]] = [:]
            var untagged: [BoardTask] = []
            for task in middle {
                if let first = task.tags.first { byTag[first.id, default: []].append(task) } else { untagged.append(task) }
            }
            for tag in tags {
                if let cards = byTag[tag.id], !cards.isEmpty { rows.append(BoardRow(kind: .tag(tag), tasks: cards)) }
            }
            if !untagged.isEmpty || byTag.isEmpty { rows.append(BoardRow(kind: .untagged, tasks: untagged)) }
        case .repository:
            var byRepo: [RepoID: [BoardTask]] = [:]
            var noRepo: [BoardTask] = []
            for task in middle {
                if let repo = task.repo { byRepo[repo, default: []].append(task) } else { noRepo.append(task) }
            }
            for repo in byRepo.keys.sorted() {
                rows.append(BoardRow(kind: .repository(repo), tasks: byRepo[repo] ?? []))
            }
            if !noRepo.isEmpty || byRepo.isEmpty { rows.append(BoardRow(kind: .noRepository, tasks: noRepo)) }
        }
        rows.append(BoardRow(kind: .lane(.later), tasks: later))
        return rows
    }

    /// GitHub labels across the given cards, for the filter menu.
    public static func labels(in tasks: [BoardTask]) -> [PRLabel] {
        var seen: [String: PRLabel] = [:]
        for label in tasks.flatMap(\.labels) where seen[label.name.lowercased()] == nil {
            seen[label.name.lowercased()] = label
        }
        return seen.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Ids of every card in the same stack as `task` (including itself), so a
    /// lane change moves the whole stack.
    public static func stackPeers(of task: BoardTask, in tasks: [BoardTask]) -> [String] {
        guard let pr = task.pullRequest, let members = task.stack?.members else { return [task.id] }
        let numbers = Set(members)
        let peers = tasks.filter { other in
            guard let otherPR = other.pullRequest else { return false }
            return otherPR.repo.lowercased() == pr.repo.lowercased() && numbers.contains(otherPR.number)
        }
        return Array(Set(peers.map(\.id) + [task.id])).sorted()
    }
}
