import Foundation
import SQLite3
@testable import AgentBoardCore

/// Fixed clock for tests: 2026-10-04 15:20 UTC.
let testNow = Date(timeIntervalSince1970: 1_791_127_200)

var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

func date(_ iso: String) -> Date {
    Timestamp.parse(iso)!
}

enum Fixtures {
    static var root: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appending(path: path))
    }
}

/// A throwaway folder laid out like a home directory, filled from the fixtures.
final class FixtureHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "agentboard-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    var paths: DataPaths {
        DataPaths(
            claudeSessions: url.appending(path: "claude/sessions", directoryHint: .isDirectory),
            claudeProjects: url.appending(path: "claude/projects", directoryHint: .isDirectory),
            codexHome: url.appending(path: "codex", directoryHint: .isDirectory)
        )
    }

    func installClaude() throws {
        try copy("claude", to: "claude")
    }

    func installCodex(threads: [CodexThreadRow]? = nil, version: Int = 5) throws {
        try copy("codex", to: "codex")
        try CodexDatabase.create(at: paths.codexHome.appending(path: "state_\(version).sqlite"),
                                 rows: threads ?? CodexThreadRow.standard(sessions: paths.codexSessions))
    }

    func copy(_ fixture: String, to destination: String) throws {
        let target = url.appending(path: destination)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixtures.root.appending(path: fixture), to: target)
    }

    func write(_ text: String, to path: String) throws {
        let target = url.appending(path: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: target)
    }

    func setModified(_ path: String, to date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.appending(path: path).path)
    }

    /// Path, size and modification date of every file, to prove reads change nothing.
    func snapshot() -> [String: String] {
        var result: [String: String] = [:]
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            result[file.path] = "\(values?.fileSize ?? -1)@\(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)"
        }
        return result
    }
}

struct CodexThreadRow {
    var id: String
    var rolloutPath: String
    var cwd: String
    var name: String?
    var title: String?
    var firstUserMessage: String?
    var gitBranch: String?
    var gitOriginURL: String?
    var archived: Int = 0
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var threadSource: String = "user"
    var source: String = "vscode"

    static func standard(sessions: URL) -> [CodexThreadRow] {
        let day4 = sessions.appending(path: "2026/10/04").path
        let day3 = sessions.appending(path: "2026/10/03").path
        return [
            CodexThreadRow(
                id: "019a0001-0000-7000-8000-000000000001",
                rolloutPath: "\(day4)/rollout-2026-10-04T13-00-00-019a0001-0000-7000-8000-000000000001.jsonl",
                cwd: "/Users/dev/work/lumen", name: "Fix CSV export rounding",
                title: "fix the csv export so totals round correctly",
                gitBranch: "codex/csv-rounding", gitOriginURL: "https://github.com/acme/lumen.git",
                createdAtMs: 1_791_118_800_000, updatedAtMs: 1_791_119_370_000
            ),
            CodexThreadRow(
                id: "019a0002-0000-7000-8000-000000000002",
                rolloutPath: "\(day4)/rollout-2026-10-04T15-00-00-019a0002-0000-7000-8000-000000000002.jsonl",
                cwd: "/Users/dev/work/orbit", name: "Add offline sync tests", title: "write tests for the offline queue",
                gitBranch: "feat/offline-sync", gitOriginURL: "git@github.com:acme/orbit.git",
                createdAtMs: 1_791_126_000_000, updatedAtMs: 1_791_126_900_000
            ),
            CodexThreadRow(
                id: "019a0003-0000-7000-8000-000000000003",
                rolloutPath: "\(day4)/rollout-sub.jsonl",
                cwd: "/Users/dev/work/orbit", name: "Independent review", title: "review",
                gitBranch: "feat/offline-sync", gitOriginURL: "https://github.com/acme/orbit.git",
                createdAtMs: 1_791_126_000_000, updatedAtMs: 1_791_126_100_000,
                threadSource: "subagent",
                source: #"{"subagent":{"thread_spawn":{"parent_thread_id":"019a0002-0000-7000-8000-000000000002","depth":1}}}"#
            ),
            CodexThreadRow(
                id: "019a0004-0000-7000-8000-000000000004",
                rolloutPath: "\(sessions.deletingLastPathComponent().path)/archived_sessions/rollout-gone.jsonl",
                cwd: "/Users/dev/work/lumen", name: "Old archived thread", title: "old",
                gitBranch: "main", gitOriginURL: "https://github.com/acme/lumen.git", archived: 1,
                createdAtMs: 1_790_000_000_000, updatedAtMs: 1_790_000_100_000
            ),
            CodexThreadRow(
                id: "019a0005-0000-7000-8000-000000000005",
                rolloutPath: "\(day4)/rollout-missing.jsonl",
                cwd: "/Users/dev/notes", name: nil, title: "Explain the sync protocol\nwith a diagram",
                createdAtMs: 1_791_100_000_000, updatedAtMs: 1_791_101_000_000
            ),
            CodexThreadRow(
                id: "019a0006-0000-7000-8000-000000000006",
                rolloutPath: "\(day3)/rollout-2026-10-03T10-00-00-019a0006-0000-7000-8000-000000000006.jsonl",
                cwd: "/Users/dev/work/lumen", name: "Theme tokens", title: "theme tokens",
                gitBranch: "codex/theme-tokens", gitOriginURL: "https://github.com/acme/lumen",
                createdAtMs: 1_791_028_800_000, updatedAtMs: 1_791_029_000_000
            ),
        ]
    }
}

/// Builds a fixture Codex database with the real `threads` column layout.
enum CodexDatabase {
    static let schema = """
    CREATE TABLE threads (
        id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
        source TEXT NOT NULL, model_provider TEXT NOT NULL, cwd TEXT NOT NULL, title TEXT NOT NULL,
        sandbox_policy TEXT NOT NULL, approval_mode TEXT NOT NULL, tokens_used INTEGER NOT NULL DEFAULT 0,
        has_user_event INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0, archived_at INTEGER,
        git_sha TEXT, git_branch TEXT, git_origin_url TEXT, cli_version TEXT NOT NULL DEFAULT '',
        first_user_message TEXT NOT NULL DEFAULT '', agent_nickname TEXT, agent_role TEXT, memory_mode TEXT,
        model TEXT, reasoning_effort TEXT, agent_path TEXT, created_at_ms INTEGER, updated_at_ms INTEGER,
        thread_source TEXT, preview TEXT NOT NULL DEFAULT '', recency_at INTEGER, recency_at_ms INTEGER,
        history_mode TEXT, name TEXT, is_pinned INTEGER NOT NULL DEFAULT 0, originator TEXT
    );
    """

    static func create(at url: URL, rows: [CodexThreadRow], schema: String = schema, keepWAL: Bool = false) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw SQLiteError(code: 1, message: "open") }
        defer { if !keepWAL { sqlite3_close(db) } }
        func exec(_ sql: String) throws {
            var error: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
                let message = error.map { String(cString: $0) } ?? "?"
                sqlite3_free(error)
                throw SQLiteError(code: 1, message: message)
            }
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec(schema)
        for row in rows {
            func q(_ s: String?) -> String { s.map { "'" + $0.replacingOccurrences(of: "'", with: "''") + "'" } ?? "NULL" }
            try exec("""
            INSERT INTO threads (id, rollout_path, created_at, updated_at, source, model_provider, cwd, title,
              sandbox_policy, approval_mode, archived, git_branch, git_origin_url, first_user_message,
              created_at_ms, updated_at_ms, thread_source, name, originator)
            VALUES (\(q(row.id)), \(q(row.rolloutPath)), \(row.createdAtMs / 1000), \(row.updatedAtMs / 1000),
              \(q(row.source)), 'openai', \(q(row.cwd)), \(q(row.title ?? "")), '{}', 'never', \(row.archived),
              \(q(row.gitBranch)), \(q(row.gitOriginURL)), \(q(row.firstUserMessage ?? "")),
              \(row.createdAtMs), \(row.updatedAtMs), \(q(row.threadSource)), \(q(row.name)), 'Codex Desktop');
            """)
        }
        if keepWAL {
            // Leave the connection open so the WAL file stays on disk, like a running app.
            openConnections.append(db)
        }
    }

    nonisolated(unsafe) static var openConnections: [OpaquePointer?] = []

    static func closeAll() {
        for db in openConnections { sqlite3_close(db) }
        openConnections.removeAll()
    }
}

/// Answers git commands from a table: directory → remotes / default branch / common dir.
final class FakeGit: GitRunning, @unchecked Sendable {
    struct Repo {
        var remotes: [String: String] = [:]
        var defaultBranch: String? = "origin/main"
        var commonDir: String?
    }

    private let lock = NSLock()
    private var repos: [String: Repo]
    private(set) var calls: [(directory: String, arguments: [String])] = []

    init(_ repos: [String: Repo]) {
        self.repos = repos
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return calls.count
    }

    func run(_ arguments: [String], in directory: String) async -> ProcessResult? {
        let repo = lock.withLock {
            calls.append((directory, arguments))
            return repos[directory]
        }
        guard let repo else { return ProcessResult(exitCode: 128, stderr: Data("fatal: not a git repository".utf8)) }
        switch arguments.first {
        case "config":
            let lines = repo.remotes.sorted { $0.key < $1.key }.map { "remote.\($0.key).url \($0.value)" }
            return ProcessResult(exitCode: lines.isEmpty ? 1 : 0, stdout: Data((lines.joined(separator: "\n") + "\n").utf8))
        case "symbolic-ref":
            guard let head = repo.defaultBranch else { return ProcessResult(exitCode: 1) }
            return ProcessResult(exitCode: 0, stdout: Data("\(head)\n".utf8))
        case "rev-parse":
            guard let common = repo.commonDir else { return ProcessResult(exitCode: 128) }
            return ProcessResult(exitCode: 0, stdout: Data("\(common)\n".utf8))
        default:
            return ProcessResult(exitCode: 1)
        }
    }
}

/// Records every `gh` invocation and answers from canned responses.
final class FakeGH: GHRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: ProcessResult] = [:]
    private var calls: [[String]] = []
    var defaultResult = ProcessResult(exitCode: 1, stderr: Data("unexpected call".utf8))

    /// Responds to calls whose arguments start with `prefix`.
    func respond(to prefix: [String], with result: ProcessResult) {
        lock.lock(); defer { lock.unlock() }
        responses[prefix.joined(separator: " ")] = result
    }

    func respond(to prefix: [String], json fixture: String) throws {
        respond(to: prefix, with: ProcessResult(exitCode: 0, stdout: try Fixtures.data(fixture)))
    }

    var recorded: [[String]] {
        lock.lock(); defer { lock.unlock() }
        return calls
    }

    /// Calls that would change something on GitHub.
    var writeCalls: [[String]] {
        recorded.filter { args in
            guard args.count >= 2 else { return false }
            return (args[0] == "pr" && ["ready", "merge", "close", "edit", "comment", "review", "create"].contains(args[1]))
                || args[0] == "api"
        }
    }

    func run(_ arguments: [String]) async throws -> ProcessResult {
        lock.withLock {
            calls.append(arguments)
            let joined = arguments.joined(separator: " ")
            let match = responses.keys.filter { joined.hasPrefix($0) }.max { $0.count < $1.count }
            return match.flatMap { responses[$0] } ?? defaultResult
        }
    }
}

extension AgentSession {
    static func make(
        _ app: AgentApp = .claude,
        id: String,
        title: String? = nil,
        cwd: String? = "/Users/dev/work/orbit",
        branch: String? = nil,
        lastActivity: Date? = testNow.addingTimeInterval(-3600),
        turn: TurnState = .ended,
        lastWrite: Date? = nil,
        archived: Bool = false
    ) -> AgentSession {
        AgentSession(
            app: app, sessionID: id, resumeID: id, title: title ?? "Session \(id)", cwd: cwd, branch: branch,
            lastActivity: lastActivity, isArchived: archived, turn: turn, lastWrite: lastWrite
        )
    }
}

extension PullRequest {
    static func make(
        _ number: Int,
        repo: String = "acme/orbit",
        branch: String,
        state: PRState = .open,
        draft: Bool = false,
        review: ReviewDecision = .none,
        checks: CheckSummary = CheckSummary(passed: 2),
        finished: Date? = nil,
        updated: Date? = nil,
        crossRepo: Bool = false,
        headOwner: String? = "acme"
    ) -> PullRequest {
        PullRequest(
            repo: repo, number: number, title: "PR \(number)", url: URL(string: "https://github.com/\(repo)/pull/\(number)"),
            headRefName: branch, headRefOid: "sha\(number)", baseRefName: "main", state: state, isDraft: draft,
            reviewDecision: review, checks: checks,
            mergedAt: state == .merged ? finished : nil, closedAt: state == .open ? nil : finished,
            updatedAt: updated ?? finished, isCrossRepository: crossRepo, headOwner: headOwner
        )
    }
}

let orbit = ResolvedRepo(id: RepoID(host: "github.com", owner: "acme", name: "orbit"), defaultBranch: "main")
let lumen = ResolvedRepo(id: RepoID(host: "github.com", owner: "acme", name: "lumen"), defaultBranch: "main")
