import Foundation
import Testing

@testable import PitwallCore

@Suite("End to end on fixtures", .serialized)
struct EngineTests {
    /// Fixture home + fake git + fake gh, with file times pinned so "working" is deterministic.
    private func makeEngine() throws -> (FixtureHome, RefreshEngine, FakeGH) {
        let home = try FixtureHome()
        try home.installClaude()
        try home.installCodex()
        try home.setModified(
            "claude/projects/-Users-dev-work-orbit/c0000002-0000-4000-8000-000000000002.jsonl", to: date("2026-10-04T15:15:00Z"))
        try home.setModified(
            "codex/sessions/2026/10/04/rollout-2026-10-04T15-00-00-019a0002-0000-7000-8000-000000000002.jsonl",
            to: date("2026-10-04T15:16:40Z"))

        let orbitRemotes = FakeGit.Repo(remotes: ["origin": "https://github.com/acme/orbit.git"])
        let lumenRemotes = FakeGit.Repo(remotes: ["origin": "git@github.com:acme/lumen.git"])
        let git = FakeGit([
            "/Users/dev/work/orbit": orbitRemotes,
            "/Users/dev/work/orbit/.claude/worktrees/calm-heron": orbitRemotes,
            "/Users/dev/work/lumen": lumenRemotes,
            "/Users/dev/work/lumen/.claude/worktrees/brave-otter": lumenRemotes,
        ])
        let gh = FakeGH()
        try gh.respond(to: ["pr", "list", "--repo", "acme/orbit"], json: "github/pr-list-acme-orbit.json")
        try gh.respond(to: ["pr", "list", "--repo", "acme/lumen"], json: "github/pr-list-acme-lumen.json")
        // Pretend the synthetic /Users/dev/... folders exist; FakeGit answers for them.
        let engine = RefreshEngine(paths: home.paths, git: git, gh: gh, directoryExists: { $0.hasPrefix("/Users/dev/work") })
        return (home, engine, gh)
    }

    @Test func buildsTheExpectedBoard() async throws {
        let (home, engine, _) = try makeEngine()
        defer { withExtendedLifetime(home) {} }
        let local = await engine.readLocal(now: testNow, calendar: utcCalendar)
        let slugs = local.githubSlugs(settings: BoardSettings())
        #expect(slugs == ["acme/lumen", "acme/orbit"])
        let github = await engine.fetchGitHub(slugs: slugs, now: testNow)
        #expect(github.errors.isEmpty)

        let board = BoardBuilder.build(
            sessions: local.sessions, repos: local.repos, pullRequests: github.pullRequests,
            settings: BoardSettings(), now: testNow)
        let columns = Dictionary(grouping: board.tasks, by: \.column).mapValues { $0.map(\.title) }

        #expect(columns[.working] == ["Add offline sync tests", "Investigate flaky upload test"])
        #expect(columns[.waiting] == ["Explain the sync protocol", "Draft release notes"])
        #expect(columns[.inReview] == ["Fix CSV export rounding"])
        #expect(columns[.ready] == nil)
        // The flaky-upload session moved back to main, but the app recorded its PR #40.
        #expect(columns[.done] == ["fix(upload): retry on 503", "Theme tokens"])

        let sync = try #require(board.tasks.first { $0.id == "github.com/acme/orbit#feat/offline-sync" })
        #expect(sync.apps == [.claude, .codex])
        #expect(sync.sessions.count == 2)
        #expect(sync.pullRequest?.number == 42)

        let csv = try #require(board.tasks.first { $0.title == "Fix CSV export rounding" })
        #expect(csv.reviewReason == .ciFailing)
        #expect(csv.pullRequest?.number == 7)

        let flaky = try #require(board.tasks.first { $0.title == "Investigate flaky upload test" })
        #expect(flaky.isDefaultBranch)
        #expect(flaky.pullRequest == nil)

        let linked = try #require(board.tasks.first { $0.id == "github.com/acme/orbit#fix/flaky-upload" })
        #expect(linked.pullRequest?.number == 40)
        #expect(linked.linkedSessionIDs == [flaky.sessions[0].id])
        #expect(linked.onBranchSessions.isEmpty)
        // The dismissed link (#35, chore/deps) never becomes a card.
        #expect(!board.tasks.contains { $0.branch == "chore/deps" })
    }

    @Test func readingNeverChangesAgentData() async throws {
        let (home, engine, _) = try makeEngine()
        let before = home.snapshot()
        let local = await engine.readLocal(now: testNow, calendar: utcCalendar)
        _ = await engine.fetchGitHub(slugs: local.githubSlugs(settings: BoardSettings()), now: testNow)
        _ = await engine.readLocal(now: testNow.addingTimeInterval(5), calendar: utcCalendar)
        #expect(home.snapshot() == before)
    }

    @Test func keepsLastGoodPRsWhenAFetchFails() async throws {
        let (home, engine, gh) = try makeEngine()
        defer { withExtendedLifetime(home) {} }
        let first = await engine.fetchGitHub(slugs: ["acme/orbit"], now: testNow)
        #expect(first.pullRequests["acme/orbit"]?.count == 11)
        gh.respond(to: ["pr", "list", "--repo", "acme/orbit"], with: ProcessResult(exitCode: 1, stderr: Data("HTTP 502".utf8)))
        let second = await engine.fetchGitHub(slugs: ["acme/orbit"], now: testNow)
        #expect(second.errors["acme/orbit"] == .failed(exitCode: 1, message: "HTTP 502"))
        #expect(second.pullRequests["acme/orbit"]?.count == 11)
        #expect(second.status(repoCount: 1).health == .error)
    }

    @Test func boardStillWorksWithoutGitHub() async throws {
        let (home, engine, _) = try makeEngine()
        defer { withExtendedLifetime(home) {} }
        let local = await engine.readLocal(now: testNow, calendar: utcCalendar)
        let board = BoardBuilder.build(
            sessions: local.sessions, repos: local.repos, pullRequests: [:], settings: BoardSettings(), now: testNow)
        #expect(board.tasks.count == 6)
        #expect(board.count(.working) == 2)
        #expect(board.count(.waiting) == 4)
    }

    @Test func demoBoardCoversEveryColumn() {
        let board = DemoData.board(now: testNow, calendar: utcCalendar)
        for column in BoardColumn.allCases {
            #expect(board.count(column) > 0, "demo data has no \(column.title) card")
        }
        #expect(board.tasks.contains { $0.apps.count == 2 })
    }
}
