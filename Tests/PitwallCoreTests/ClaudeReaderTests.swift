import Foundation
import Testing
@testable import PitwallCore

@Suite("Claude reader")
struct ClaudeReaderTests {
    private func line(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    private func user(_ content: Any, branch: String? = "feat/x", sidechain: Bool = false, meta: Bool = false) -> Data {
        var o: [String: Any] = ["type": "user", "isSidechain": sidechain, "message": ["role": "user", "content": content], "timestamp": "2026-10-04T10:00:00.000Z"]
        if let branch { o["gitBranch"] = branch }
        if meta { o["isMeta"] = true }
        return line(o)
    }

    private func assistant(stop: String?, branch: String? = "feat/x", sidechain: Bool = false, at time: String = "2026-10-04T10:00:05.000Z") -> Data {
        var message: [String: Any] = ["role": "assistant", "content": [["type": "text", "text": "ok"]]]
        if let stop { message["stop_reason"] = stop }
        var o: [String: Any] = ["type": "assistant", "isSidechain": sidechain, "message": message, "timestamp": time]
        if let branch { o["gitBranch"] = branch }
        return line(o)
    }

    private let stopHook = #"{"type":"system","subtype":"stop_hook_summary","stopReason":"","isSidechain":false,"timestamp":"2026-10-04T10:00:06.000Z","gitBranch":"feat/x"}"#
    private let bookkeeping = [#"{"type":"last-prompt","lastPrompt":"x"}"#, #"{"type":"custom-title","customTitle":"x"}"#, #"{"type":"cost-state"}"#]

    // MARK: Turn state rules

    @Test func endedTurnFinishesWithStopHookSummary() {
        let lines = [user("do it"), assistant(stop: "end_turn"), Data(stopHook.utf8)] + bookkeeping.map { Data($0.utf8) }
        #expect(ClaudeTranscript.summarize(lines: lines).turn == .ended)
    }

    @Test func assistantEndTurnWithoutHookIsEnded() {
        #expect(ClaudeTranscript.summarize(lines: [user("do it"), assistant(stop: "end_turn")]).turn == .ended)
    }

    @Test func pendingToolUseIsRunning() {
        #expect(ClaudeTranscript.summarize(lines: [user("do it"), assistant(stop: "tool_use")]).turn == .running)
    }

    @Test func freshPromptAndToolResultAreRunning() {
        #expect(ClaudeTranscript.summarize(lines: [assistant(stop: "end_turn"), Data(stopHook.utf8), user("next")]).turn == .running)
        let toolResult = user([["type": "tool_result", "tool_use_id": "t1", "content": "ok"]])
        #expect(ClaudeTranscript.summarize(lines: [assistant(stop: "tool_use"), toolResult]).turn == .running)
    }

    @Test func userInterruptEndsTheTurn() {
        let interrupt = user([["type": "text", "text": "[Request interrupted by user for tool use]"]])
        #expect(ClaudeTranscript.summarize(lines: [assistant(stop: "tool_use"), interrupt]).turn == .ended)
    }

    @Test func sidechainAndMetaLinesAreIgnored() {
        let lines = [user("go"), assistant(stop: "tool_use"), assistant(stop: "end_turn", sidechain: true), user("<local-command-caveat>", meta: true)]
        #expect(ClaudeTranscript.summarize(lines: lines).turn == .running)
    }

    @Test func apiErrorCountsAsRunning() {
        let error = Data(#"{"type":"system","subtype":"api_error","timestamp":"2026-10-04T10:00:07.000Z"}"#.utf8)
        #expect(ClaudeTranscript.summarize(lines: [user("go"), error]).turn == .running)
    }

    @Test func onlyBookkeepingIsUnknown() {
        #expect(ClaudeTranscript.summarize(lines: bookkeeping.map { Data($0.utf8) }).turn == .unknown)
    }

    // MARK: Branch

    @Test func branchComesFromTheMostRecentLineThatHasOne() {
        let lines = [user("a", branch: "claude/calm-heron"), assistant(stop: "tool_use", branch: "feat/renamed"), Data(#"{"type":"mode","mode":"default"}"#.utf8)]
        #expect(ClaudeTranscript.summarize(lines: lines).branch == "feat/renamed")
    }

    @Test func detachedHeadIsNotABranch() {
        let lines = [user("a", branch: "feat/old"), assistant(stop: "end_turn", branch: "HEAD")]
        #expect(ClaudeTranscript.summarize(lines: lines).branch == "feat/old")
    }

    @Test func malformedLinesAreSkipped() {
        let lines = [Data("garbage".utf8), user("a"), Data("{\"truncated\":".utf8), assistant(stop: "end_turn")]
        let summary = ClaudeTranscript.summarize(lines: lines)
        #expect(summary.turn == .ended)
        #expect(summary.branch == "feat/x")
    }

    @Test func encodesProjectFolderNames() {
        #expect(ClaudeTranscript.encodeProjectDirectory("/Users/dev/work/orbit") == "-Users-dev-work-orbit")
        #expect(ClaudeTranscript.encodeProjectDirectory("/Users/dev/work/orbit/.claude/worktrees/calm-heron")
            == "-Users-dev-work-orbit--claude-worktrees-calm-heron")
        #expect(ClaudeTranscript.encodeProjectDirectory("/tmp/my project_1") == "-tmp-my-project-1")
    }

    // MARK: Reader against the fixture tree

    @Test func readsSessionsFromFixtureTree() throws {
        let home = try FixtureHome()
        try home.installClaude()
        let reader = ClaudeReader(paths: home.paths)
        let result = reader.read(now: testNow, calendar: utcCalendar)

        // Four readable session files; the malformed one and the tombstone are skipped.
        #expect(result.items.count == 4)
        let byTitle = Dictionary(uniqueKeysWithValues: result.items.map { ($0.title, $0) })

        let sync = try #require(byTitle["Add offline sync queue"])
        #expect(sync.sessionID == "local_11111111-aaaa-4aaa-8aaa-000000000001")
        #expect(sync.resumeID == "c0000001-0000-4000-8000-000000000001")
        #expect(sync.branch == "feat/offline-sync") // transcript beats metadata "claude/calm-heron"
        #expect(sync.turn == .ended)
        #expect(sync.isArchived == false)
        #expect(sync.createdAt == Date(timeIntervalSince1970: 1_791_122_400))
        #expect(sync.lastActivity == Date(timeIntervalSince1970: 1_791_125_000)) // metadata is newer than the tail
        #expect(sync.problem == nil)
        #expect(sync.resumeCommand == "cd /Users/dev/work/orbit/.claude/worktrees/calm-heron && claude --resume c0000001-0000-4000-8000-000000000001")
        #expect(!sync.activity.isEmpty)

        let flaky = try #require(byTitle["Investigate flaky upload test"])
        #expect(flaky.branch == "main")
        // Dismissed and non-GitHub PR links are dropped.
        #expect(flaky.linkedPullRequests == [LinkedPullRequest(repo: RepoID(host: "github.com", owner: "acme", name: "orbit"), branch: "fix/flaky-upload", number: 40)])
        #expect(flaky.turn == .running) // the sidechain end_turn is ignored
        #expect(flaky.lastWrite != nil)

        let notes = try #require(byTitle["Draft release notes"])
        #expect(notes.problem == "Can't find transcript")
        #expect(notes.branch == "claude/brave-otter") // metadata fallback
        #expect(notes.turn == .unknown)

        let archived = try #require(byTitle["Fix date parsing"])
        #expect(archived.isArchived)
        #expect(archived.branch == "fix/date-parsing") // found via the transcript index
        #expect(archived.turn == .ended) // interrupted by user

        let statuses = Dictionary(uniqueKeysWithValues: result.statuses.map { ($0.kind, $0) })
        #expect(statuses[.claudeSessions]?.health == .warning)
        #expect(statuses[.claudeSessions]?.detail.contains("Can't read 1 of 5") == true)
        #expect(statuses[.claudeTranscripts]?.health == .warning)
    }

    @Test func missingAppFolderIsReportedNotThrown() {
        let reader = ClaudeReader(sessionsRoot: URL(filePath: "/nonexistent/claude/sessions"), projectsRoot: URL(filePath: "/nonexistent/claude/projects"))
        let result = reader.read(now: testNow)
        #expect(result.items.isEmpty)
        #expect(result.statuses.first?.health == .missing)
    }

    @Test func readsOnlyTheTailOfLargeTranscripts() throws {
        let home = try FixtureHome()
        try home.installClaude()
        // Inflate the transcript to ~6 MB by prepending filler before the real lines.
        let path = "claude/projects/-Users-dev-work-orbit--claude-worktrees-calm-heron/c0000001-0000-4000-8000-000000000001.jsonl"
        let original = try String(contentsOf: home.url.appending(path: path), encoding: .utf8)
        let filler = String(repeating: "{\"type\":\"user\",\"message\":{\"content\":\"\(String(repeating: "z", count: 400))\"},\"timestamp\":\"2026-10-01T00:00:00.000Z\",\"gitBranch\":\"old/branch\"}\n", count: 14_000)
        try home.write(filler + original, to: path)
        // Make the session look old so only the state window (256 KB) is read.
        try home.setModified(path, to: date("2026-10-04T14:43:02Z"))
        let reader = ClaudeReader(paths: home.paths)
        let result = reader.read(now: date("2026-10-10T12:00:00Z"), calendar: utcCalendar)

        let sync = try #require(result.items.first { $0.title == "Add offline sync queue" })
        #expect(sync.branch == "feat/offline-sync")
        #expect(sync.turn == .ended)
        // Every transcript read stays within its tail window, never the whole 6 MB file.
        #expect(reader.lastTranscriptBytesRead <= 4 * 256 * 1024)
    }

    @Test func cachesUnchangedFiles() throws {
        let home = try FixtureHome()
        try home.installClaude()
        let reader = ClaudeReader(paths: home.paths)
        _ = reader.read(now: testNow, calendar: utcCalendar)
        _ = reader.read(now: testNow, calendar: utcCalendar)
        #expect(reader.lastTranscriptBytesRead == 0)
    }
}

@Suite("Opening sessions in their apps")
struct AppLinkTests {
    @Test func claudeAndCodexDeepLinks() {
        let claude = AgentSession.make(.claude, id: "local_11111111-aaaa-4aaa-8aaa-000000000001")
        #expect(claude.appURL?.absoluteString == "claude://claude.ai/epitaxy/local_11111111-aaaa-4aaa-8aaa-000000000001")
        let codex = AgentSession.make(.codex, id: "019a0001-0000-7000-8000-000000000001")
        #expect(codex.appURL?.absoluteString == "codex://threads/019a0001-0000-7000-8000-000000000001")
    }

    @Test func oddIdentifiersAreEscaped() {
        #expect(AgentSession.make(.codex, id: "a/b?c").appURL?.absoluteString == "codex://threads/a%2Fb%3Fc")
        #expect(AgentSession.make(.claude, id: "").appURL == nil)
    }

    @Test func doubleClickOpensTheNewestSessionOnTheBranch() {
        let older = AgentSession.make(.claude, id: "old", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-600))
        let newer = AgentSession.make(.codex, id: "new", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-60))
        var linkedOnly = AgentSession.make(.claude, id: "linked", branch: "main", lastActivity: testNow)
        linkedOnly.linkedPullRequests = [LinkedPullRequest(repo: orbit.id, branch: "feat/x", number: 1)]
        let board = BoardBuilder.build(sessions: [older, newer, linkedOnly], repos: [older.id: orbit, newer.id: orbit, linkedOnly.id: orbit],
                                       pullRequests: ["acme/orbit": [.make(1, branch: "feat/x")]], settings: BoardSettings(), now: testNow)
        let task = board.tasks.first { $0.branch == "feat/x" }
        #expect(task?.sessionToOpen?.id == newer.id) // not the linked session, even though it's newer
    }
}
