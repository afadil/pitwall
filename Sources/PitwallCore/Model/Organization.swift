import Foundation

/// Horizontal lanes: your priority, independent of the automatic status columns.
public enum Lane: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case fast
    case normal
    case later

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fast: "Fast lane"
        case .normal: "Normal"
        case .later: "Later"
        }
    }
}

/// A small, muted palette so tags never compete with the accent or CI colours.
public enum TagColor: String, Codable, CaseIterable, Sendable, Hashable, Identifiable {
    case orange, red, pink, purple, blue, teal, green, gray

    public var id: String { rawValue }
}

public struct CardTag: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var color: TagColor

    public init(id: UUID = UUID(), name: String, color: TagColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// What you set on one card. Keyed by task id (repo + branch, or the session for
/// default-branch cards), so it carries over to new sessions on the same branch.
public struct CardOrganization: Codable, Hashable, Sendable {
    /// nil means Normal.
    public var lane: Lane?
    public var tagIDs: [UUID]
    public var hidden: Bool
    /// Last time the card was on the board; entries unseen for 30 days are pruned.
    public var lastSeen: Date

    public init(lane: Lane? = nil, tagIDs: [UUID] = [], hidden: Bool = false, lastSeen: Date) {
        self.lane = lane
        self.tagIDs = tagIDs
        self.hidden = hidden
        self.lastSeen = lastSeen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lane = try? c.decodeIfPresent(Lane.self, forKey: .lane)
        tagIDs = (try? c.decode([UUID].self, forKey: .tagIDs)) ?? []
        hidden = (try? c.decode(Bool.self, forKey: .hidden)) ?? false
        lastSeen = (try? c.decode(Date.self, forKey: .lastSeen)) ?? Date()
    }

    var isEmpty: Bool { (lane == nil || lane == .normal) && tagIDs.isEmpty && !hidden }
}

/// Lanes, tags and hidden cards, stored in Pitwall's own JSON file.
public struct Organization: Codable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let pruneAfter: TimeInterval = 30 * 24 * 3600

    public var version: Int
    public var tags: [CardTag]
    public var cards: [String: CardOrganization]

    public init(tags: [CardTag] = [], cards: [String: CardOrganization] = [:]) {
        self.version = Self.currentVersion
        self.tags = tags
        self.cards = cards
    }

    // Tolerant: a missing or malformed part never loses the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? Self.currentVersion
        tags = (try? c.decode([Lenient<CardTag>].self, forKey: .tags))?.compactMap(\.value) ?? []
        cards = ((try? c.decode([String: Lenient<CardOrganization>].self, forKey: .cards)) ?? [:]).compactMapValues(\.value)
        let known = Set(tags.map(\.id))
        for key in cards.keys {
            cards[key]?.tagIDs.removeAll { !known.contains($0) }
        }
    }

    // MARK: Queries

    public func lane(for taskID: String) -> Lane? {
        cards[taskID]?.lane
    }

    /// The card's tags in the order of the tag list.
    public func tags(for taskID: String) -> [CardTag] {
        guard let ids = cards[taskID]?.tagIDs, !ids.isEmpty else { return [] }
        let set = Set(ids)
        return tags.filter { set.contains($0.id) }
    }

    public func isHidden(_ taskID: String) -> Bool {
        cards[taskID]?.hidden ?? false
    }

    public func tag(named name: String) -> CardTag? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        return tags.first { $0.name.lowercased() == key }
    }

    // MARK: Changes

    public mutating func setLane(_ lane: Lane, for taskIDs: [String], now: Date = Date()) {
        for id in taskIDs {
            update(id, now: now) { $0.lane = lane == .normal ? nil : lane }
        }
    }

    public mutating func setTag(_ tagID: UUID, on: Bool, for taskID: String, now: Date = Date()) {
        guard tags.contains(where: { $0.id == tagID }) else { return }
        update(taskID, now: now) { card in
            card.tagIDs.removeAll { $0 == tagID }
            if on { card.tagIDs.append(tagID) }
        }
    }

    public mutating func setHidden(_ hidden: Bool, for taskID: String, now: Date = Date()) {
        update(taskID, now: now) { $0.hidden = hidden }
    }

    /// Creates a tag, or returns the existing one with the same name (case-insensitive).
    @discardableResult
    public mutating func createTag(named name: String, color: TagColor? = nil) -> CardTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = tag(named: trimmed) { return existing }
        let palette = TagColor.allCases
        let tag = CardTag(name: String(trimmed.prefix(40)), color: color ?? palette[tags.count % palette.count])
        tags.append(tag)
        return tag
    }

    public mutating func renameTag(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = tags.firstIndex(where: { $0.id == id }) else { return }
        if let clash = tag(named: trimmed), clash.id != id { return }
        tags[index].name = String(trimmed.prefix(40))
    }

    public mutating func recolorTag(_ id: UUID, to color: TagColor) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        tags[index].color = color
    }

    public mutating func deleteTag(_ id: UUID) {
        tags.removeAll { $0.id == id }
        for key in Array(cards.keys) {
            cards[key]?.tagIDs.removeAll { $0 == id }
            if cards[key]?.isEmpty == true { cards[key] = nil }
        }
    }

    /// Records that these cards are on the board. Returns true when something
    /// changed enough to be worth saving (at most once a day per card).
    @discardableResult
    public mutating func markSeen(_ taskIDs: some Sequence<String>, now: Date = Date()) -> Bool {
        var changed = false
        for id in taskIDs {
            guard let seen = cards[id]?.lastSeen, now.timeIntervalSince(seen) > 24 * 3600 else { continue }
            cards[id]?.lastSeen = now
            changed = true
        }
        return changed
    }

    /// Drops entries for cards that haven't been on the board for 30 days.
    @discardableResult
    public mutating func prune(now: Date = Date()) -> Bool {
        let before = cards.count
        cards = cards.filter { now.timeIntervalSince($0.value.lastSeen) <= Self.pruneAfter && !$0.value.isEmpty }
        return cards.count != before
    }

    private mutating func update(_ id: String, now: Date, _ change: (inout CardOrganization) -> Void) {
        var card = cards[id] ?? CardOrganization(lastSeen: now)
        change(&card)
        card.lastSeen = now
        cards[id] = card.isEmpty ? nil : card
    }
}
