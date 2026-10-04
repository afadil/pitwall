import Foundation

public enum BoardColumn: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case working
    case waiting
    case inReview
    case ready
    case done

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .working: "Working"
        case .waiting: "Waiting on you"
        case .inReview: "In review"
        case .ready: "Ready to merge"
        case .done: "Done"
        }
    }
}

/// Why an open PR sits in "In review". Shown on the card.
public enum ReviewReason: String, Sendable, Codable, Hashable {
    case draft
    case ciFailing
    case changesRequested
    case ciRunning
    case awaitingReview

    public var label: String {
        switch self {
        case .draft: "Draft"
        case .ciFailing: "CI failing"
        case .changesRequested: "Changes requested"
        case .ciRunning: "CI running"
        case .awaitingReview: "Awaiting review"
        }
    }
}

/// One card: a (repo, branch) pair and the sessions working on it.
public struct BoardTask: Sendable, Identifiable, Hashable {
    public var id: String
    public var repo: RepoID?
    public var branch: String?
    public var isDefaultBranch: Bool
    /// Sessions on this branch first (newest first), then sessions linked only by a PR.
    public var sessions: [AgentSession]
    /// Sessions that opened this task's PR but have since moved to another branch.
    public var linkedSessionIDs: Set<String>
    public var pullRequest: PullRequest?
    public var column: BoardColumn
    public var reviewReason: ReviewReason?
    public var isHidden: Bool

    public init(
        id: String,
        repo: RepoID?,
        branch: String?,
        isDefaultBranch: Bool,
        sessions: [AgentSession],
        linkedSessionIDs: Set<String> = [],
        pullRequest: PullRequest?,
        column: BoardColumn,
        reviewReason: ReviewReason?,
        isHidden: Bool = false
    ) {
        self.id = id
        self.repo = repo
        self.branch = branch
        self.isDefaultBranch = isDefaultBranch
        self.sessions = sessions
        self.linkedSessionIDs = linkedSessionIDs
        self.pullRequest = pullRequest
        self.column = column
        self.reviewReason = reviewReason
        self.isHidden = isHidden
    }

    public var primarySession: AgentSession? { sessions.first }

    /// Sessions currently on this task's branch.
    public var onBranchSessions: [AgentSession] {
        sessions.filter { !linkedSessionIDs.contains($0.id) }
    }

    /// The newest on-branch session's title; for a card that exists only because
    /// of a linked PR, the PR title describes it better.
    public var title: String {
        onBranchSessions.first?.title ?? pullRequest?.title ?? primarySession?.title ?? branch ?? "Untitled task"
    }

    /// Newest activity on this branch. Linked sessions don't count: their recent
    /// activity happened on another branch.
    public var lastActivity: Date? {
        onBranchSessions.compactMap(\.lastActivity).max()
    }

    /// Most recent of session activity and PR updates; used for sorting.
    public var sortDate: Date {
        [lastActivity, pullRequest?.updatedAt, pullRequest?.finishedAt].compactMap { $0 }.max() ?? .distantPast
    }

    public var apps: [AgentApp] {
        Array(Set(sessions.map(\.app))).sorted()
    }

    public var isTurnRunning: Bool {
        onBranchSessions.contains { $0.turn == .running }
    }

    public var isArchived: Bool {
        !sessions.isEmpty && sessions.allSatisfy(\.isArchived)
    }

    /// Folder to open: the newest session's working directory.
    public var directory: String? {
        sessions.lazy.compactMap(\.cwd).first { FileManager.default.fileExists(atPath: $0) }
            ?? sessions.lazy.compactMap(\.cwd).first
    }

    /// `repo · branch` line for the card.
    public var locationLine: String {
        let repoName = repo?.displayName ?? directory.map { ($0 as NSString).lastPathComponent } ?? "No repository"
        guard let branch else { return repoName }
        return "\(repoName) · \(branch)"
    }

    public var problems: [String] {
        sessions.compactMap(\.problem)
    }
}

public struct Board: Sendable {
    /// Visible tasks, already filtered and sorted newest first.
    public var tasks: [BoardTask]
    /// Every repo seen, including excluded ones, for Settings.
    public var repos: [RepoID]
    public var generatedAt: Date

    public init(tasks: [BoardTask], repos: [RepoID], generatedAt: Date) {
        self.tasks = tasks
        self.repos = repos
        self.generatedAt = generatedAt
    }

    public static let empty = Board(tasks: [], repos: [], generatedAt: .distantPast)

    public func tasks(in column: BoardColumn) -> [BoardTask] {
        tasks.filter { $0.column == column }
    }

    public func count(_ column: BoardColumn) -> Int {
        tasks.reduce(0) { $0 + ($1.column == column ? 1 : 0) }
    }

    public func task(id: String?) -> BoardTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }
}
