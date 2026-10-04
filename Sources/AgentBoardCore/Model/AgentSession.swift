import Foundation

/// The desktop app a session belongs to.
public enum AgentApp: String, Sendable, Codable, CaseIterable, Hashable, Comparable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    public static func < (lhs: AgentApp, rhs: AgentApp) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Whether the agent's most recent turn is still running, as far as the tail shows.
public enum TurnState: String, Sendable, Codable, Hashable {
    case running
    case ended
    case unknown
}

/// One Claude session or Codex thread, normalised.
public struct AgentSession: Sendable, Identifiable, Hashable {
    public var app: AgentApp
    /// Claude `sessionId` (`local_…`) or Codex thread `id`.
    public var sessionID: String
    /// Claude `cliSessionId` or Codex thread `id`: what the resume command needs.
    public var resumeID: String
    public var title: String
    public var cwd: String?
    public var branch: String?
    /// Remote URL recorded by the app itself (Codex `git_origin_url`).
    public var originURL: String?
    /// Extra directories that may resolve to the repository when `cwd` is gone.
    public var fallbackDirectories: [String]
    public var createdAt: Date?
    public var lastActivity: Date?
    public var isArchived: Bool
    public var turn: TurnState
    /// Newest modification time of files that only change while a turn runs
    /// (transcript plus sub-agent sidecars). Used to spot stalled turns.
    public var lastWrite: Date?
    /// Clustered activity spans seen in the tail, used for the timeline.
    public var activity: [DateInterval]
    /// A short "can't read …" note when part of this session could not be parsed.
    public var problem: String?

    public init(
        app: AgentApp,
        sessionID: String,
        resumeID: String,
        title: String,
        cwd: String? = nil,
        branch: String? = nil,
        originURL: String? = nil,
        fallbackDirectories: [String] = [],
        createdAt: Date? = nil,
        lastActivity: Date? = nil,
        isArchived: Bool = false,
        turn: TurnState = .unknown,
        lastWrite: Date? = nil,
        activity: [DateInterval] = [],
        problem: String? = nil
    ) {
        self.app = app
        self.sessionID = sessionID
        self.resumeID = resumeID
        self.title = title
        self.cwd = cwd
        self.branch = branch
        self.originURL = originURL
        self.fallbackDirectories = fallbackDirectories
        self.createdAt = createdAt
        self.lastActivity = lastActivity
        self.isArchived = isArchived
        self.turn = turn
        self.lastWrite = lastWrite
        self.activity = activity
        self.problem = problem
    }

    public var id: String { "\(app.rawValue):\(sessionID)" }

    /// Shell command that resumes this session from Terminal.
    ///
    /// Claude looks sessions up per project directory, so the command changes
    /// into the session's folder first.
    public var resumeCommand: String? {
        guard !resumeID.isEmpty else { return nil }
        let base = switch app {
        case .claude: "claude --resume \(resumeID)"
        case .codex: "codex resume \(resumeID)"
        }
        guard let cwd, !cwd.isEmpty else { return base }
        return "cd \(Shell.quote(cwd)) && \(base)"
    }
}

enum Shell {
    /// POSIX single-quote escaping.
    static func quote(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:@,")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
