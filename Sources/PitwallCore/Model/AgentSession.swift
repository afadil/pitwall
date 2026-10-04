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

/// A pull request the app itself recorded for a session (Claude's `prs` metadata).
/// Lets a PR stay linked to its session after the checkout moves to another branch.
public struct LinkedPullRequest: Sendable, Hashable {
    public var repo: RepoID
    public var branch: String
    public var number: Int?

    public init(repo: RepoID, branch: String, number: Int?) {
        self.repo = repo
        self.branch = branch
        self.number = number
    }
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
    /// Whether `cwd` existed when the session was read (worktrees get deleted).
    public var cwdExists: Bool
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
    public var linkedPullRequests: [LinkedPullRequest]

    public init(
        app: AgentApp,
        sessionID: String,
        resumeID: String,
        title: String,
        cwd: String? = nil,
        cwdExists: Bool = false,
        branch: String? = nil,
        originURL: String? = nil,
        fallbackDirectories: [String] = [],
        createdAt: Date? = nil,
        lastActivity: Date? = nil,
        isArchived: Bool = false,
        turn: TurnState = .unknown,
        lastWrite: Date? = nil,
        activity: [DateInterval] = [],
        problem: String? = nil,
        linkedPullRequests: [LinkedPullRequest] = []
    ) {
        self.app = app
        self.sessionID = sessionID
        self.resumeID = resumeID
        self.title = title
        self.cwd = cwd
        self.cwdExists = cwdExists
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
        self.linkedPullRequests = linkedPullRequests
    }

    public var id: String { "\(app.rawValue):\(sessionID)" }

    /// Deep link that opens this session in its own app.
    ///
    /// - Claude: `claude://claude.ai/epitaxy/<sessionId>`, the form the Claude app
    ///   uses for its own session links.
    /// - Codex: `codex://threads/<thread id>`, the route the Codex app registers.
    public var appURL: URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard !sessionID.isEmpty, let id = sessionID.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        switch app {
        case .claude: return URL(string: "claude://claude.ai/epitaxy/\(id)")
        case .codex: return URL(string: "codex://threads/\(id)")
        }
    }

    /// Shell command that resumes this session from Terminal.
    ///
    /// Claude looks sessions up per project directory, so the command changes
    /// into the session's folder first.
    public var resumeCommand: String? {
        guard !resumeID.isEmpty else { return nil }
        let base =
            switch app {
            case .claude: "claude --resume \(resumeID)"
            case .codex: "codex resume \(resumeID)"
            }
        guard let cwd, !cwd.isEmpty else { return base }
        return "cd \(Shell.quote(cwd)) && \(base)"
    }
}
