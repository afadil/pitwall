import Foundation

/// Reads Codex desktop threads from `state_<n>.sqlite` (read-only) and rollout tails.
public final class CodexReader {
    public let codexHome: URL
    public var stateTailBytes = 128 * 1024
    public var activityTailBytes = 2 * 1024 * 1024
    public var maxTailBytes = 8 * 1024 * 1024

    static let requiredColumns: Set<String> = ["id", "rollout_path", "cwd"]
    static let optionalColumns: [String] = [
        "title", "name", "preview", "first_user_message", "git_branch", "git_origin_url",
        "archived", "created_at_ms", "created_at", "updated_at_ms", "updated_at",
        "thread_source", "source", "agent_role",
    ]

    private var rolloutCache: [String: (FileStamp, Date?, CodexRolloutSummary)] = [:]
    public private(set) var lastRolloutBytesRead = 0

    public init(codexHome: URL) {
        self.codexHome = codexHome
    }

    /// The highest-numbered `state_<n>.sqlite`, since the file name is versioned.
    public func stateDatabase() -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: codexHome.path)) ?? []
        let versions: [(Int, String)] = names.compactMap { name in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite") else { return nil }
            let digits = name.dropFirst("state_".count).dropLast(".sqlite".count)
            guard let version = Int(digits) else { return nil }
            return (version, name)
        }
        guard let best = versions.max(by: { $0.0 < $1.0 }) else { return nil }
        return codexHome.appending(path: best.1)
    }

    public func read(now: Date = Date(), calendar: Calendar = .current) -> SourceRead<AgentSession> {
        lastRolloutBytesRead = 0
        let sessionsDir = codexHome.appending(path: "sessions", directoryHint: .isDirectory)
        guard let database = stateDatabase() else {
            let missing = !FileManager.default.fileExists(atPath: codexHome.path)
            return SourceRead(items: [], statuses: [
                SourceStatus(kind: .codexThreads, path: codexHome.appending(path: "state_*.sqlite").path,
                             health: .missing,
                             detail: missing ? "Not found. Is the Codex desktop app installed?" : "No state_*.sqlite database found"),
                SourceStatus(kind: .codexRollouts, path: sessionsDir.path, health: .missing, detail: "No threads to look up"),
            ])
        }

        let rows: [[String: Any]]
        let columns: Set<String>
        do {
            let db = try ReadOnlySQLite(path: database.path)
            columns = try db.columns(of: "threads")
            if columns.isEmpty {
                throw SQLiteError(code: 1, message: "no threads table")
            }
            let missing = Self.requiredColumns.subtracting(columns)
            if !missing.isEmpty {
                throw SQLiteError(code: 1, message: "threads table is missing \(missing.sorted().joined(separator: ", "))")
            }
            let selected = (Array(Self.requiredColumns) + Self.optionalColumns.filter(columns.contains))
                .map(ReadOnlySQLite.quoteIdentifier)
                .joined(separator: ", ")
            rows = try db.query("SELECT \(selected) FROM threads")
        } catch {
            return SourceRead(items: [], statuses: [
                SourceStatus(kind: .codexThreads, path: database.path, health: .error, detail: "Can't read \(database.lastPathComponent): \(error)"),
                SourceStatus(kind: .codexRollouts, path: sessionsDir.path, health: .missing, detail: "No threads to look up"),
            ])
        }

        let startOfDay = calendar.startOfDay(for: now)
        var sessions: [AgentSession] = []
        var skippedRows = 0
        var rolloutProblems = 0
        var rolloutsRead = 0

        for row in rows {
            guard let id = row.string("id") else {
                skippedRows += 1
                continue
            }
            // Sub-agent threads appear nested under their parent in the app.
            if row.string("thread_source") == "subagent" { continue }
            if let source = row.string("source"), source.hasPrefix("{"), source.contains("\"subagent\"") { continue }

            let created = Self.millis(row["created_at_ms"]) ?? Self.seconds(row["created_at"])
            let updated = Self.millis(row["updated_at_ms"]) ?? Self.seconds(row["updated_at"])
            var session = AgentSession(
                app: .codex,
                sessionID: id,
                resumeID: id,
                title: Self.title(for: row),
                cwd: row.string("cwd"),
                cwdExists: row.string("cwd").map(FileManager.default.fileExists(atPath:)) ?? false,
                branch: row.string("git_branch").flatMap { $0 == "HEAD" ? nil : $0 },
                originURL: row.string("git_origin_url"),
                createdAt: created,
                lastActivity: updated,
                isArchived: (row["archived"] as? Int64).map { $0 != 0 } ?? false
            )

            if session.isArchived {
                // Archived threads are hidden by default and their rollouts move; skip the read.
                session.turn = .ended
            } else if let path = row.string("rollout_path") {
                let url = URL(filePath: path)
                let activeToday = (updated ?? .distantPast) >= startOfDay
                    || (FileStamp(url)?.modified ?? .distantPast) >= startOfDay
                do {
                    let summary = try rolloutSummary(at: url, activitySince: activeToday ? startOfDay : nil)
                    rolloutsRead += 1
                    session.turn = summary.turn
                    if let last = summary.lastTimestamp {
                        session.lastActivity = max(session.lastActivity ?? last, last)
                    }
                    session.activity = Timeline.cluster(summary.activityTimestamps)
                    if summary.turn == .running { session.lastWrite = FileStamp(url)?.modified }
                } catch {
                    session.problem = FileManager.default.fileExists(atPath: path) ? "Can't read rollout" : "Can't find rollout"
                    rolloutProblems += 1
                }
            }
            sessions.append(session)
        }

        sessions.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        let archived = sessions.filter(\.isArchived).count
        var detail = "\(sessions.count) thread\(sessions.count == 1 ? "" : "s")"
        if archived > 0 { detail += " · \(archived) archived" }
        detail += " · \(database.lastPathComponent)"

        let threadStatus = skippedRows > 0
            ? SourceStatus(kind: .codexThreads, path: database.path, health: .warning, detail: "Can't read \(skippedRows) rows. \(detail)")
            : SourceStatus(kind: .codexThreads, path: database.path, health: .ok, detail: detail)
        let active = sessions.count - archived
        let rolloutStatus = rolloutProblems > 0
            ? SourceStatus(kind: .codexRollouts, path: sessionsDir.path, health: .warning, detail: "Can't read \(rolloutProblems) of \(active) rollouts")
            : SourceStatus(kind: .codexRollouts, path: sessionsDir.path, health: .ok, detail: "\(rolloutsRead) rollout\(rolloutsRead == 1 ? "" : "s") · tails only")
        return SourceRead(items: sessions, statuses: [threadStatus, rolloutStatus])
    }

    /// Thread name as the app shows it: `name`, then `title`, then the first prompt line.
    static func title(for row: [String: Any]) -> String {
        for key in ["name", "title", "preview", "first_user_message"] {
            guard let value = row.string(key) else { continue }
            let firstLine = value.split(whereSeparator: \.isNewline).first.map(String.init) ?? value
            let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return String(trimmed.prefix(120)) }
        }
        return "Untitled thread"
    }

    static func millis(_ value: Any?) -> Date? {
        switch value {
        case let v as Int64: v > 0 ? Date(timeIntervalSince1970: Double(v) / 1000) : nil
        case let v as Double: v > 0 ? Date(timeIntervalSince1970: v / 1000) : nil
        case let s as String: Timestamp.parse(s)
        default: nil
        }
    }

    static func seconds(_ value: Any?) -> Date? {
        switch value {
        case let v as Int64: Timestamp.fromEpoch(Double(v))
        case let v as Double: Timestamp.fromEpoch(v)
        case let s as String: Timestamp.parse(s)
        default: nil
        }
    }

    private func rolloutSummary(at url: URL, activitySince: Date?) throws -> CodexRolloutSummary {
        guard let stamp = FileStamp(url) else { throw CocoaError(.fileReadNoSuchFile) }
        if let cached = rolloutCache[url.path], cached.0 == stamp, cached.1 == activitySince {
            return cached.2
        }
        var summary = CodexRolloutSummary()
        let initial = activitySince == nil ? stateTailBytes : activityTailBytes
        let tail = try TailReader.read(url, initialBytes: initial, limit: maxTailBytes) { tail in
            summary = CodexRollout.summarize(lines: tail.lines, activitySince: activitySince)
            return summary.turn != .unknown
        }
        lastRolloutBytesRead += tail.bytesRead
        rolloutCache[url.path] = (stamp, activitySince, summary)
        return summary
    }
}
