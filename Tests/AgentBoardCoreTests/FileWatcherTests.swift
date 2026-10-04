import Foundation
import Testing
@testable import AgentBoardCore

@Suite("File watcher")
struct FileWatcherTests {
    @Test func reportsRelevantChangesOnly() async throws {
        let home = try FixtureHome()
        defer { withExtendedLifetime(home) {} }
        let paths = home.paths
        try FileManager.default.createDirectory(at: paths.claudeProjects.appending(path: "-p"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.codexHome, withIntermediateDirectories: true)

        let counter = Counter()
        let watcher = FileWatcher(paths: [paths.claudeProjects, paths.codexHome], latency: 0.1,
                                  filter: FileWatcher.relevantFilter(paths: paths)) { counter.increment() }
        defer { withExtendedLifetime(watcher) {} }
        try await Task.sleep(for: .milliseconds(300))

        // Noise the app writes constantly (Codex logs) must not trigger a refresh.
        try home.write("x", to: "codex/logs_2.sqlite-wal")
        try await Task.sleep(for: .milliseconds(800))
        #expect(counter.value == 0)

        try home.write("{}\n", to: "claude/projects/-p/session.jsonl")
        for _ in 0..<30 where counter.value == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(counter.value > 0)
    }

    @Test func filterMatchesTheAgentFiles() {
        let paths = DataPaths.standard(home: URL(filePath: "/Users/dev"))
        let filter = FileWatcher.relevantFilter(paths: paths)
        #expect(filter("/Users/dev/Library/Application Support/Claude/claude-code-sessions/a/b/local_1.json"))
        #expect(filter("/Users/dev/.claude/projects/-x/abc.jsonl"))
        #expect(filter("/Users/dev/.codex/sessions/2026/10/04/rollout-1.jsonl"))
        #expect(filter("/Users/dev/.codex/state_5.sqlite"))
        #expect(filter("/Users/dev/.codex/state_5.sqlite-wal"))
        #expect(!filter("/Users/dev/.codex/logs_2.sqlite-wal"))
        #expect(!filter("/Users/dev/.claude/projects/-x/memory/notes.md"))
        #expect(!filter("/Users/dev/Documents/other.jsonl"))
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
