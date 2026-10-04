import Foundation
import Testing
@testable import PitwallCore

@Suite("Tail reader and timestamps")
struct TailReaderTests {
    @Test func readsOnlyTheEndOfALargeFile() throws {
        let home = try FixtureHome()
        // ~3 MB of filler followed by three real lines.
        let filler = String(repeating: "{\"type\":\"filler\",\"pad\":\"\(String(repeating: "x", count: 200))\"}\n", count: 15_000)
        try home.write(filler + "{\"n\":1}\n{\"n\":2}\n{\"n\":3}\n", to: "big.jsonl")

        let tail = try TailReader.read(home.url.appending(path: "big.jsonl"), maxBytes: 64 * 1024)
        #expect(tail.bytesRead == 64 * 1024)
        #expect(tail.fileSize > 3_000_000)
        #expect(!tail.coversWholeFile)
        #expect(tail.lines.suffix(3).map { String(decoding: $0, as: UTF8.self) } == ["{\"n\":1}", "{\"n\":2}", "{\"n\":3}"])
        // The partial first line of the window is dropped, so every line is valid JSON.
        #expect(tail.lines.allSatisfy { JSONLine.object($0) != nil })
    }

    @Test func smallFileKeepsItsFirstLine() throws {
        let home = try FixtureHome()
        try home.write("{\"a\":1}\n{\"b\":2}", to: "small.jsonl")
        let tail = try TailReader.read(home.url.appending(path: "small.jsonl"), maxBytes: 1024)
        #expect(tail.coversWholeFile)
        #expect(tail.lines.count == 2)
    }

    @Test func growsTheWindowUntilSatisfied() throws {
        let home = try FixtureHome()
        let marker = "{\"marker\":true}\n"
        let filler = String(repeating: "{\"pad\":\"\(String(repeating: "y", count: 100))\"}\n", count: 2_000)
        try home.write(marker + filler, to: "grow.jsonl")
        let tail = try TailReader.read(home.url.appending(path: "grow.jsonl"), initialBytes: 4096, limit: 1 << 20) { tail in
            tail.lines.contains { JSONLine.object($0)?["marker"] != nil }
        }
        #expect(tail.lines.contains { JSONLine.object($0)?["marker"] != nil })
    }

    @Test func missingFileThrows() {
        #expect(throws: (any Error).self) {
            try TailReader.read(URL(filePath: "/nonexistent/pitwall/file.jsonl"), maxBytes: 10)
        }
    }

    @Test func parsesTimestampsFromBothApps() {
        #expect(Timestamp.parse("2026-10-04T19:21:37.039Z")?.timeIntervalSince1970 == 1_791_141_697.039)
        #expect(Timestamp.parse("2026-10-04T19:21:37Z")?.timeIntervalSince1970 == 1_791_141_697)
        #expect(Timestamp.parse("2026-10-04T15:21:37-04:00")?.timeIntervalSince1970 == 1_791_141_697)
        #expect(Timestamp.parse("not a date") == nil)
        // Claude metadata stores epoch milliseconds.
        #expect(Timestamp.parse(NSNumber(value: 1_791_141_767_736))?.timeIntervalSince1970 == 1_791_141_767.736)
        #expect(Timestamp.parse(NSNumber(value: 1_791_141_767))?.timeIntervalSince1970 == 1_791_141_767)
    }

    @Test func clustersActivityIntoBlocks() {
        let base = date("2026-10-04T10:00:00Z")
        let stamps = [0, 60, 120, 240, 1200, 1260, 4000].map { base.addingTimeInterval(TimeInterval($0)) }
        let spans = Timeline.cluster(stamps, gap: 300, minimumLength: 120)
        #expect(spans.count == 3)
        #expect(spans[0].start == base && spans[0].duration == 240)
        #expect(spans[1].duration == 120) // 60 s padded to the minimum
        #expect(spans[2].start == base.addingTimeInterval(4000))
    }

    @Test func mergesParallelSessionsPerApp() {
        let base = date("2026-10-04T10:00:00Z")
        func block(_ app: AgentApp, _ start: TimeInterval, _ end: TimeInterval, _ id: String) -> TimelineBlock {
            TimelineBlock(app: app, taskID: nil, sessionID: id, interval: DateInterval(start: base.addingTimeInterval(start), end: base.addingTimeInterval(end)))
        }
        let blocks = [block(.claude, 0, 600, "a"), block(.claude, 300, 900, "b"), block(.claude, 960, 1200, "c"), block(.codex, 0, 60, "d")]
        #expect(Timeline.merged(blocks, app: .claude).count == 2)
        #expect(Timeline.merged(blocks, app: .claude, joiningGap: 120).count == 1)
        #expect(Timeline.activeDuration(blocks, app: .claude) == 900 + 240)
        #expect(Timeline.activeDuration(blocks, app: .codex) == 60)
    }
}
