import Foundation
import Testing

@testable import PitwallCore

@Suite("Codex reader", .serialized)
struct CodexReaderTests {
    @Test func readsThreadsFromDatabaseAndRollouts() throws {
        let home = try FixtureHome()
        try home.installCodex()
        let reader = CodexReader(codexHome: home.paths.codexHome)
        let result = reader.read(now: testNow, calendar: utcCalendar)

        // The sub-agent thread is excluded; the archived one is kept and flagged.
        #expect(result.items.count == 5)
        let byID = Dictionary(uniqueKeysWithValues: result.items.map { ($0.sessionID, $0) })
        #expect(byID["019a0003-0000-7000-8000-000000000003"] == nil)

        let csv = try #require(byID["019a0001-0000-7000-8000-000000000001"])
        #expect(csv.title == "Fix CSV export rounding")  // `name` wins over `title`
        #expect(csv.branch == "codex/csv-rounding")
        #expect(csv.originURL == "https://github.com/acme/lumen.git")
        #expect(csv.turn == .ended)
        #expect(csv.resumeCommand == "cd /Users/dev/work/lumen && codex resume 019a0001-0000-7000-8000-000000000001")
        #expect(csv.lastActivity == date("2026-10-04T13:09:30.2Z"))
        // 13:00–13:04 and 13:09 are within the 8-minute gap, so one span.
        #expect(csv.activity.count == 1)
        #expect(csv.activity.first?.start == date("2026-10-04T13:00:00Z"))

        let sync = try #require(byID["019a0002-0000-7000-8000-000000000002"])
        #expect(sync.turn == .running)  // task_started without task_complete
        #expect(sync.lastWrite != nil)

        let archived = try #require(byID["019a0004-0000-7000-8000-000000000004"])
        #expect(archived.isArchived)
        #expect(archived.problem == nil)  // archived rollouts move; that's not a problem

        let untitled = try #require(byID["019a0005-0000-7000-8000-000000000005"])
        #expect(untitled.title == "Explain the sync protocol")  // first line of `title`
        #expect(untitled.branch == nil)
        #expect(untitled.problem == "Can't find rollout")

        let aborted = try #require(byID["019a0006-0000-7000-8000-000000000006"])
        #expect(aborted.turn == .ended)  // turn_aborted

        let statuses = Dictionary(uniqueKeysWithValues: result.statuses.map { ($0.kind, $0) })
        #expect(statuses[.codexThreads]?.health == .ok)
        #expect(statuses[.codexThreads]?.detail == "5 threads · 1 archived · state_5.sqlite")
        #expect(statuses[.codexRollouts]?.health == .warning)
    }

    @Test func picksTheHighestVersionedDatabase() throws {
        let home = try FixtureHome()
        try home.installCodex(version: 5)
        try CodexDatabase.create(at: home.paths.codexHome.appending(path: "state_4.sqlite"), rows: [])
        try home.write("not sqlite", to: "codex/state_x.sqlite")
        let reader = CodexReader(codexHome: home.paths.codexHome)
        #expect(reader.stateDatabase()?.lastPathComponent == "state_5.sqlite")
        try CodexDatabase.create(at: home.paths.codexHome.appending(path: "state_12.sqlite"), rows: [])
        #expect(reader.stateDatabase()?.lastPathComponent == "state_12.sqlite")
    }

    @Test func missingColumnsShowCantReadInsteadOfCrashing() throws {
        let home = try FixtureHome()
        try FileManager.default.createDirectory(at: home.paths.codexHome, withIntermediateDirectories: true)
        try CodexDatabase.create(
            at: home.paths.codexHome.appending(path: "state_6.sqlite"), rows: [],
            schema: "CREATE TABLE threads (id TEXT, cwd TEXT, title TEXT);")
        let result = CodexReader(codexHome: home.paths.codexHome).read(now: testNow)
        #expect(result.items.isEmpty)
        #expect(result.statuses.first?.health == .error)
        #expect(result.statuses.first?.detail.contains("Can't read state_6.sqlite") == true)
        #expect(result.statuses.first?.detail.contains("rollout_path") == true)
    }

    @Test func corruptDatabaseShowsCantRead() throws {
        let home = try FixtureHome()
        try home.write("this is not a database", to: "codex/state_5.sqlite")
        let result = CodexReader(codexHome: home.paths.codexHome).read(now: testNow)
        #expect(result.items.isEmpty)
        #expect(result.statuses.first?.health == .error)
    }

    @Test func missingCodexFolderIsReported() {
        let result = CodexReader(codexHome: URL(filePath: "/nonexistent/.codex")).read(now: testNow)
        #expect(result.statuses.first?.health == .missing)
    }

    @Test func readingWithoutWALCreatesNoFiles() throws {
        let home = try FixtureHome()
        try home.installCodex()
        let db = home.paths.codexHome.appending(path: "state_5.sqlite").path
        // Apple's SQLite may leave an empty -wal behind; remove it and any -shm to
        // match the real Codex folder, which has neither.
        try? FileManager.default.removeItem(atPath: db + "-wal")
        try? FileManager.default.removeItem(atPath: db + "-shm")
        let before = home.snapshot()
        let result = CodexReader(codexHome: home.paths.codexHome).read(now: testNow, calendar: utcCalendar)
        #expect(result.items.count == 5)
        #expect(home.snapshot() == before)
        #expect(!FileManager.default.fileExists(atPath: db + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: db + "-shm"))
    }

    @Test func seesUncheckpointedRowsWhileTheAppHoldsTheDatabase() throws {
        let home = try FixtureHome()
        try home.copy("codex", to: "codex")
        let url = home.paths.codexHome.appending(path: "state_5.sqlite")
        try CodexDatabase.create(at: url, rows: CodexThreadRow.standard(sessions: home.paths.codexSessions), keepWAL: true)
        defer { CodexDatabase.closeAll() }
        let walSize = (try FileManager.default.attributesOfItem(atPath: url.path + "-wal")[.size] as? NSNumber)?.intValue ?? 0
        #expect(walSize > 0)
        let before = home.snapshot()
        let result = CodexReader(codexHome: home.paths.codexHome).read(now: testNow, calendar: utcCalendar)
        #expect(result.items.count == 5)
        // Read from a private copy: the live database, WAL and index are untouched.
        #expect(home.snapshot() == before)
    }

    @Test func rolloutTailRules() {
        func event(_ type: String, _ time: String) -> Data {
            Data(#"{"timestamp":"\#(time)","type":"event_msg","payload":{"type":"\#(type)"}}"#.utf8)
        }
        let item = Data(#"{"timestamp":"2026-10-04T10:05:00.000Z","type":"response_item","payload":{"type":"message"}}"#.utf8)
        #expect(CodexRollout.summarize(lines: [event("task_started", "2026-10-04T10:00:00.000Z"), item]).turn == .running)
        #expect(
            CodexRollout.summarize(lines: [
                event("task_started", "2026-10-04T10:00:00.000Z"), event("task_complete", "2026-10-04T10:06:00.000Z"),
            ]).turn == .ended)
        #expect(CodexRollout.summarize(lines: [item]).turn == .unknown)
        #expect(CodexRollout.summarize(lines: [Data("{not json".utf8), event("turn_aborted", "2026-10-04T10:06:00.000Z")]).turn == .ended)
    }
}
