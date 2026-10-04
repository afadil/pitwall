import Foundation

/// Fields we use from `claude-code-sessions/<a>/<b>/local_*.json`.
public struct ClaudeSessionMetadata: Sendable, Hashable {
    public var sessionID: String
    public var cliSessionID: String?
    public var title: String?
    public var isArchived: Bool
    public var createdAt: Date?
    public var lastActivityAt: Date?
    public var cwd: String?
    public var originCwd: String?
    public var gitRoots: [String]
    /// Present on worktree sessions in newer app versions.
    public var branch: String?
    /// Pull requests the app linked to this session (`prs`), minus dismissed ones.
    public var pullRequests: [LinkedPullRequest]

    /// Parses one session file. Unknown keys are ignored; wrong types become nil.
    public static func parse(_ data: Data, fallbackID: String) -> ClaudeSessionMetadata? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let anchors = (object["gitAnchors"] as? [[String: Any]]) ?? []
        return ClaudeSessionMetadata(
            sessionID: object.string("sessionId") ?? fallbackID,
            cliSessionID: object.string("cliSessionId"),
            title: object.string("title"),
            isArchived: object.bool("isArchived") ?? false,
            createdAt: object.date("createdAt"),
            lastActivityAt: object.date("lastActivityAt"),
            cwd: object.string("cwd"),
            originCwd: object.string("originCwd"),
            gitRoots: anchors.compactMap { $0.string("gitRoot") },
            branch: object.string("branch"),
            pullRequests: ((object["prs"] as? [[String: Any]]) ?? []).compactMap(linkedPullRequest)
        )
    }

    /// `{prNumber, repo: "owner/name", host, branch, dismissed?}` → link, GitHub only.
    static func linkedPullRequest(_ entry: [String: Any]) -> LinkedPullRequest? {
        guard entry.bool("dismissed") != true,
              let slug = entry.string("repo"), let branch = entry.string("branch") else { return nil }
        let host = entry.string("host") ?? "github.com"
        guard host.lowercased() == "github.com" else { return nil }
        let parts = slug.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let number = (entry["prNumber"] as? NSNumber)?.intValue
        return LinkedPullRequest(repo: RepoID(host: host, owner: parts[0], name: parts[1]), branch: branch, number: number)
    }
}

struct FileStamp: Hashable {
    var size: UInt64
    var modified: Date?

    init?(_ url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attributes[.modificationDate] as? Date
    }
}

/// Reads Claude desktop sessions. Read-only: files are opened for reading and
/// parsed results are cached by size and modification date.
public final class ClaudeReader {
    public let sessionsRoot: URL
    public let projectsRoot: URL
    /// Window used to find the branch and turn state.
    public var stateTailBytes = 256 * 1024
    /// Larger window for sessions active today, to draw the timeline.
    public var activityTailBytes = 2 * 1024 * 1024
    /// Hard cap when a single huge line hides everything else.
    public var maxTailBytes = 8 * 1024 * 1024

    private var metadataCache: [String: (FileStamp, ClaudeSessionMetadata)] = [:]
    private var transcriptCache: [String: (FileStamp, Date?, ClaudeTranscriptSummary)] = [:]
    /// Total bytes read from transcripts in the last `read` call (for tests).
    public private(set) var lastTranscriptBytesRead = 0

    public init(sessionsRoot: URL, projectsRoot: URL) {
        self.sessionsRoot = sessionsRoot
        self.projectsRoot = projectsRoot
    }

    public convenience init(paths: DataPaths) {
        self.init(sessionsRoot: paths.claudeSessions, projectsRoot: paths.claudeProjects)
    }

    public func read(now: Date = Date(), calendar: Calendar = .current) -> SourceRead<AgentSession> {
        lastTranscriptBytesRead = 0
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sessionsRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return SourceRead(items: [], statuses: [
                SourceStatus(kind: .claudeSessions, path: sessionsRoot.path, health: .missing, detail: "Not found. Is the Claude desktop app installed?"),
                SourceStatus(kind: .claudeTranscripts, path: projectsRoot.path, health: .missing, detail: "No sessions to look up"),
            ])
        }

        let files: [URL]
        do {
            files = try sessionFiles()
        } catch {
            return SourceRead(items: [], statuses: [
                SourceStatus(kind: .claudeSessions, path: sessionsRoot.path, health: .error, detail: "Can't read folder: \(error.localizedDescription)"),
            ])
        }

        let startOfDay = calendar.startOfDay(for: now)
        var transcriptIndex: [String: URL]?
        var sessions: [AgentSession] = []
        var unreadableFiles = 0
        var transcriptsRead = 0
        var transcriptProblems = 0

        for file in files {
            guard let metadata = metadata(at: file) else {
                unreadableFiles += 1
                continue
            }

            var session = AgentSession(
                app: .claude,
                sessionID: metadata.sessionID,
                resumeID: metadata.cliSessionID ?? "",
                title: metadata.title ?? "Untitled session",
                cwd: metadata.cwd ?? metadata.originCwd,
                branch: metadata.branch,
                fallbackDirectories: [metadata.originCwd].compactMap { $0 } + metadata.gitRoots,
                createdAt: metadata.createdAt,
                lastActivity: metadata.lastActivityAt,
                isArchived: metadata.isArchived,
                linkedPullRequests: metadata.pullRequests
            )

            guard let cli = metadata.cliSessionID else {
                session.problem = "Can't find transcript: session has no CLI id"
                transcriptProblems += 1
                sessions.append(session)
                continue
            }

            var transcriptURL = candidateTranscripts(for: metadata, cli: cli).first { fm.fileExists(atPath: $0.path) }
            if transcriptURL == nil {
                if transcriptIndex == nil { transcriptIndex = buildTranscriptIndex() }
                transcriptURL = transcriptIndex?[cli]
            }
            guard let transcriptURL else {
                session.problem = "Can't find transcript"
                transcriptProblems += 1
                sessions.append(session)
                continue
            }

            let activeToday = (metadata.lastActivityAt ?? .distantPast) >= startOfDay
                || (FileStamp(transcriptURL)?.modified ?? .distantPast) >= startOfDay
            do {
                let summary = try transcriptSummary(at: transcriptURL, activitySince: activeToday ? startOfDay : nil)
                transcriptsRead += 1
                if let branch = summary.branch { session.branch = branch }
                if let last = summary.lastTimestamp {
                    session.lastActivity = max(session.lastActivity ?? last, last)
                }
                session.turn = summary.turn
                session.activity = Timeline.cluster(summary.activityTimestamps)
                if summary.turn == .running {
                    session.lastWrite = lastWrite(transcript: transcriptURL)
                }
            } catch {
                session.problem = "Can't read transcript"
                transcriptProblems += 1
            }
            sessions.append(session)
        }

        sessions.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }

        let archived = sessions.filter(\.isArchived).count
        var sessionDetail = "\(sessions.count) session\(sessions.count == 1 ? "" : "s")"
        if archived > 0 { sessionDetail += " · \(archived) archived" }
        let sessionsStatus: SourceStatus
        if unreadableFiles > 0 {
            sessionsStatus = SourceStatus(
                kind: .claudeSessions, path: sessionsRoot.path,
                health: sessions.isEmpty ? .error : .warning,
                detail: "Can't read \(unreadableFiles) of \(files.count) session files. \(sessionDetail) shown."
            )
        } else {
            sessionsStatus = SourceStatus(kind: .claudeSessions, path: sessionsRoot.path, health: .ok, detail: sessionDetail)
        }

        let transcriptsStatus: SourceStatus
        if !fm.fileExists(atPath: projectsRoot.path) {
            transcriptsStatus = SourceStatus(kind: .claudeTranscripts, path: projectsRoot.path, health: sessions.isEmpty ? .missing : .error, detail: "Not found. Branches and turn state are unavailable.")
        } else if transcriptProblems > 0 {
            transcriptsStatus = SourceStatus(kind: .claudeTranscripts, path: projectsRoot.path, health: .warning, detail: "Can't read \(transcriptProblems) of \(sessions.count) transcripts")
        } else {
            transcriptsStatus = SourceStatus(kind: .claudeTranscripts, path: projectsRoot.path, health: .ok, detail: "\(transcriptsRead) transcript\(transcriptsRead == 1 ? "" : "s") · tails only")
        }

        return SourceRead(items: sessions, statuses: [sessionsStatus, transcriptsStatus])
    }

    // MARK: - Files

    /// `local_*.json` files up to three levels below the root (two in practice).
    func sessionFiles() throws -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        var queue: [(URL, Int)] = [(sessionsRoot, 0)]
        while let (directory, depth) = queue.popLast() {
            let entries: [URL]
            if depth == 0 {
                entries = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])
            } else {
                entries = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            }
            for entry in entries {
                let name = entry.lastPathComponent
                if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if depth < 3 { queue.append((entry, depth + 1)) }
                } else if name.hasPrefix("local_"), name.hasSuffix(".json") {
                    result.append(entry)
                }
            }
        }
        return result.sorted { $0.path < $1.path }
    }

    private func metadata(at url: URL) -> ClaudeSessionMetadata? {
        guard let stamp = FileStamp(url) else { return nil }
        if let cached = metadataCache[url.path], cached.0 == stamp { return cached.1 }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let fallbackID = url.deletingPathExtension().lastPathComponent
        guard let parsed = ClaudeSessionMetadata.parse(data, fallbackID: fallbackID) else { return nil }
        metadataCache[url.path] = (stamp, parsed)
        return parsed
    }

    private func candidateTranscripts(for metadata: ClaudeSessionMetadata, cli: String) -> [URL] {
        [metadata.cwd, metadata.originCwd].compactMap { $0 }.map {
            projectsRoot
                .appending(path: ClaudeTranscript.encodeProjectDirectory($0), directoryHint: .isDirectory)
                .appending(path: "\(cli).jsonl")
        }
    }

    /// cliSessionId → transcript, for sessions whose folder name we can't predict.
    private func buildTranscriptIndex() -> [String: URL] {
        let fm = FileManager.default
        var index: [String: URL] = [:]
        let projects = (try? fm.contentsOfDirectory(at: projectsRoot, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let files = (try? fm.contentsOfDirectory(atPath: project.path)) ?? []
            for name in files where name.hasSuffix(".jsonl") {
                index[String(name.dropLast(6))] = project.appending(path: name)
            }
        }
        return index
    }

    private func transcriptSummary(at url: URL, activitySince: Date?) throws -> ClaudeTranscriptSummary {
        guard let stamp = FileStamp(url) else { throw CocoaError(.fileReadNoSuchFile) }
        if let cached = transcriptCache[url.path], cached.0 == stamp, cached.1 == activitySince {
            return cached.2
        }
        var summary = ClaudeTranscriptSummary()
        let initial = activitySince == nil ? stateTailBytes : activityTailBytes
        let tail = try TailReader.read(url, initialBytes: initial, limit: maxTailBytes) { tail in
            summary = ClaudeTranscript.summarize(lines: tail.lines, activitySince: activitySince)
            return summary.turn != .unknown && summary.branch != nil
        }
        lastTranscriptBytesRead += tail.bytesRead
        transcriptCache[url.path] = (stamp, activitySince, summary)
        return summary
    }

    /// Newest write to the transcript or its sub-agent sidecar files.
    private func lastWrite(transcript: URL) -> Date? {
        var dates = [FileStamp(transcript)?.modified].compactMap { $0 }
        let sidecar = transcript.deletingPathExtension().appending(path: "subagents", directoryHint: .isDirectory)
        if let entries = try? FileManager.default.contentsOfDirectory(at: sidecar, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for entry in entries where entry.pathExtension == "jsonl" {
                if let date = try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate {
                    dates.append(date)
                }
            }
        }
        return dates.max()
    }
}
