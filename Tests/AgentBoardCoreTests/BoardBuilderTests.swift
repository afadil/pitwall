import Foundation
import Testing
@testable import AgentBoardCore

@Suite("Grouping sessions into tasks")
struct BoardBuilderTests {
    private func build(
        _ sessions: [AgentSession],
        repos: [String: ResolvedRepo]? = nil,
        prs: [String: [PullRequest]] = [:],
        settings: BoardSettings = BoardSettings()
    ) -> Board {
        let map = repos ?? Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, orbit) })
        return BoardBuilder.build(sessions: sessions, repos: map, pullRequests: prs, settings: settings, now: testNow)
    }

    @Test func claudeAndCodexOnTheSameBranchShareOneCard() throws {
        let claude = AgentSession.make(.claude, id: "c1", title: "Add offline sync queue", branch: "feat/offline-sync", lastActivity: testNow.addingTimeInterval(-600))
        let codex = AgentSession.make(.codex, id: "x1", title: "Add offline sync tests", branch: "feat/offline-sync", lastActivity: testNow.addingTimeInterval(-300))
        let board = build([claude, codex])
        #expect(board.tasks.count == 1)
        let task = try #require(board.tasks.first)
        #expect(task.id == "github.com/acme/orbit#feat/offline-sync")
        #expect(task.apps == [.claude, .codex])
        #expect(task.title == "Add offline sync tests") // newest session first
        #expect(task.locationLine == "acme/orbit · feat/offline-sync")
    }

    @Test func sameBranchNameInDifferentReposStaysSeparate() {
        let a = AgentSession.make(id: "a", branch: "feat/x")
        let b = AgentSession.make(.codex, id: "b", branch: "feat/x")
        let board = build([a, b], repos: [a.id: orbit, b.id: lumen])
        #expect(board.tasks.count == 2)
    }

    @Test func defaultBranchAndBranchlessSessionsGetTheirOwnCards() {
        let main1 = AgentSession.make(id: "m1", branch: "main")
        let main2 = AgentSession.make(.codex, id: "m2", branch: "main")
        let none = AgentSession.make(id: "n1", branch: nil)
        let board = build([main1, main2, none])
        #expect(board.tasks.count == 3)
        #expect(board.tasks.allSatisfy { $0.id.hasPrefix("session:") })
        #expect(board.tasks.first { $0.id == "session:claude:m1" }?.isDefaultBranch == true)
    }

    @Test func sessionsOutsideAnyRepoGetTheirOwnCards() {
        let a = AgentSession.make(id: "a", cwd: "/tmp/notes", branch: "feat/x")
        let b = AgentSession.make(id: "b", cwd: "/tmp/notes", branch: "feat/x")
        let board = build([a, b], repos: [:])
        #expect(board.tasks.count == 2)
        #expect(board.tasks.first?.locationLine == "notes · feat/x")
    }

    @Test func attachesTheMatchingPullRequest() throws {
        let s = AgentSession.make(id: "a", branch: "feat/offline-sync")
        let pr = PullRequest.make(42, branch: "feat/offline-sync", review: .approved)
        let board = build([s], prs: ["acme/orbit": [pr, .make(43, branch: "other")]])
        let task = try #require(board.tasks.first)
        #expect(task.pullRequest?.number == 42)
        #expect(task.column == .ready)
    }

    @Test func defaultBranchNeverMatchesAPullRequest() throws {
        let s = AgentSession.make(id: "a", branch: "main")
        let pr = PullRequest.make(36, branch: "main", crossRepo: true, headOwner: "contributor")
        let task = try #require(build([s], prs: ["acme/orbit": [pr]]).tasks.first)
        #expect(task.pullRequest == nil)
        #expect(task.column == .waiting)
    }

    @Test func archivedSessionsAreHiddenUnlessAsked() {
        let live = AgentSession.make(id: "a", branch: "feat/a")
        let archived = AgentSession.make(id: "b", branch: "feat/b", archived: true)
        #expect(build([live, archived]).tasks.count == 1)
        #expect(build([live, archived], settings: BoardSettings(showArchived: true)).tasks.count == 2)
    }

    @Test func hiddenCardsAndExcludedRepos() {
        let a = AgentSession.make(id: "a", branch: "feat/a")
        let b = AgentSession.make(.codex, id: "b", branch: "feat/b")
        let hideA = BoardSettings(hiddenTaskIDs: ["github.com/acme/orbit#feat/a"])
        #expect(build([a, b], settings: hideA).tasks.map(\.id) == ["github.com/acme/orbit#feat/b"])

        var showHidden = hideA
        showHidden.showHidden = true
        let shown = build([a, b], settings: showHidden)
        #expect(shown.tasks.count == 2)
        #expect(shown.tasks.first { $0.id.hasSuffix("feat/a") }?.isHidden == true)

        let excluded = build([a, b], repos: [a.id: orbit, b.id: lumen], settings: BoardSettings(excludedRepos: ["github.com/acme/lumen"]))
        #expect(excluded.tasks.count == 1)
        // Excluded repos still appear in the repo list so they can be re-included.
        #expect(excluded.repos.map(\.key).contains("github.com/acme/lumen"))
    }

    @Test func tasksWithOldFinishedPRsLeaveTheBoard() {
        let s = AgentSession.make(id: "a", branch: "fix/date-parsing", lastActivity: testNow.addingTimeInterval(-20 * 86400))
        let pr = PullRequest.make(38, branch: "fix/date-parsing", state: .merged, finished: testNow.addingTimeInterval(-14 * 86400))
        #expect(build([s], prs: ["acme/orbit": [pr]]).tasks.isEmpty)
    }

    @Test func sortsNewestFirstWithinColumns() {
        let old = AgentSession.make(id: "old", branch: "feat/old", lastActivity: testNow.addingTimeInterval(-7200))
        let new = AgentSession.make(id: "new", branch: "feat/new", lastActivity: testNow.addingTimeInterval(-60))
        #expect(build([old, new]).tasks(in: .waiting).map(\.branch) == ["feat/new", "feat/old"])
    }

    @Test func timelineBlocksAreClippedToTheDay() {
        var s = AgentSession.make(id: "a", branch: "feat/a")
        let day = utcCalendar.dateInterval(of: .day, for: testNow)!
        s.activity = [DateInterval(start: day.start.addingTimeInterval(-600), duration: 1200), DateInterval(start: testNow.addingTimeInterval(-300), duration: 120)]
        let blocks = Timeline.blocks(for: build([s]).tasks, in: day)
        #expect(blocks.count == 2)
        #expect(blocks[0].interval.start == day.start)
        #expect(blocks[0].interval.duration == 600)
        #expect(Timeline.activeDuration(blocks, app: .claude) == 720)
    }
}
