import Foundation

/// Where each app keeps its data. Overridable so tests and demos never touch real folders.
public struct DataPaths: Sendable, Hashable {
    public var claudeSessions: URL
    public var claudeProjects: URL
    public var codexHome: URL

    public init(claudeSessions: URL, claudeProjects: URL, codexHome: URL) {
        self.claudeSessions = claudeSessions
        self.claudeProjects = claudeProjects
        self.codexHome = codexHome
    }

    public static func standard(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> DataPaths {
        DataPaths(
            claudeSessions: home.appending(path: "Library/Application Support/Claude/claude-code-sessions", directoryHint: .isDirectory),
            claudeProjects: home.appending(path: ".claude/projects", directoryHint: .isDirectory),
            codexHome: home.appending(path: ".codex", directoryHint: .isDirectory)
        )
    }

    public var codexSessions: URL {
        codexHome.appending(path: "sessions", directoryHint: .isDirectory)
    }
}

public enum FolderOpener: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case finder
    case terminal
    case editor

    public var id: String { rawValue }
}

/// User preferences. Stored by the app; the core only reads them.
public struct BoardSettings: Sendable, Codable, Hashable {
    public var refreshInterval: TimeInterval
    public var showArchived: Bool
    public var showHidden: Bool
    public var excludedRepos: Set<String>
    /// Hidden cards from before organization.json existed. Read once on launch to
    /// move them there; nothing else uses it.
    public var hiddenTaskIDs: Set<String>
    public var folderOpener: FolderOpener
    public var showMenuBarExtra: Bool
    public var grouping: Grouping
    /// Cards the fast lane is meant to hold; the lane header warns above it.
    public var fastLaneLimit: Int

    public init(
        refreshInterval: TimeInterval = 60,
        showArchived: Bool = false,
        showHidden: Bool = false,
        excludedRepos: Set<String> = [],
        hiddenTaskIDs: Set<String> = [],
        folderOpener: FolderOpener = .finder,
        showMenuBarExtra: Bool = true,
        grouping: Grouping = .lane,
        fastLaneLimit: Int = 3
    ) {
        self.refreshInterval = refreshInterval
        self.showArchived = showArchived
        self.showHidden = showHidden
        self.excludedRepos = excludedRepos
        self.hiddenTaskIDs = hiddenTaskIDs
        self.folderOpener = folderOpener
        self.showMenuBarExtra = showMenuBarExtra
        self.grouping = grouping
        self.fastLaneLimit = fastLaneLimit
    }

    public static let refreshChoices: [TimeInterval] = [30, 60, 120, 300]

    // Decode tolerantly so a settings change between versions never loses the rest.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BoardSettings()
        refreshInterval = (try? c.decode(TimeInterval.self, forKey: .refreshInterval)) ?? d.refreshInterval
        showArchived = (try? c.decode(Bool.self, forKey: .showArchived)) ?? d.showArchived
        showHidden = (try? c.decode(Bool.self, forKey: .showHidden)) ?? d.showHidden
        excludedRepos = (try? c.decode(Set<String>.self, forKey: .excludedRepos)) ?? d.excludedRepos
        hiddenTaskIDs = (try? c.decode(Set<String>.self, forKey: .hiddenTaskIDs)) ?? d.hiddenTaskIDs
        folderOpener = (try? c.decode(FolderOpener.self, forKey: .folderOpener)) ?? d.folderOpener
        showMenuBarExtra = (try? c.decode(Bool.self, forKey: .showMenuBarExtra)) ?? d.showMenuBarExtra
        grouping = (try? c.decode(Grouping.self, forKey: .grouping)) ?? d.grouping
        fastLaneLimit = max(1, (try? c.decode(Int.self, forKey: .fastLaneLimit)) ?? d.fastLaneLimit)
    }
}
