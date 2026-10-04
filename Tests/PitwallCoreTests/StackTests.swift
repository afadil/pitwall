import Foundation
import Testing
@testable import PitwallCore

/// A stack: main ← feat/a (#1) ← feat/b (#2) ← feat/c (#3).
@Suite("Stacked pull requests")
struct StackTests {
    private func pr(_ number: Int, _ head: String, base: String, state: PRState = .open, crossRepo: Bool = false) -> PullRequest {
        var pr = PullRequest.make(number, branch: head, state: state, review: .approved, finished: state == .open ? nil : testNow.addingTimeInterval(-3600),
                                  updated: testNow.addingTimeInterval(-3600), crossRepo: crossRepo)
        pr.baseRefName = base
        return pr
    }

    private let stack = [
        (1, "feat/a", "main"),
        (2, "feat/b", "feat/a"),
        (3, "feat/c", "feat/b"),
    ]

    private func board(workingOn branch: String?, extraPRs: [PullRequest] = []) -> Board {
        // One session that opened all three PRs; it's on `branch` (or main) and maybe running.
        var session = AgentSession.make(id: "s", title: "Loans", branch: branch ?? "main",
                                        lastActivity: testNow.addingTimeInterval(-60), turn: branch == nil ? .ended : .running)
        session.linkedPullRequests = stack.map { LinkedPullRequest(repo: orbit.id, branch: $0.1, number: $0.0) }
        let prs = stack.map { pr($0.0, $0.1, base: $0.2) } + extraPRs
        return BoardBuilder.build(sessions: [session], repos: [session.id: orbit], pullRequests: ["acme/orbit": prs],
                                  settings: BoardSettings(), now: testNow)
    }

    private func task(_ board: Board, _ number: Int) -> BoardTask? {
        board.tasks.first { $0.pullRequest?.number == number }
    }

    @Test func workingOnTheTopPullsTheWholeStackIntoWorking() throws {
        let b = board(workingOn: "feat/c")
        #expect(task(b, 3)?.column == .working)
        #expect(task(b, 3)?.stack?.workingVia == nil) // working on its own account
        for number in [1, 2] {
            let t = try #require(task(b, number))
            #expect(t.column == .working)
            #expect(t.stack?.workingVia == 3)
            #expect(t.reviewReason == nil)
        }
        #expect(task(b, 1)?.stack?.members == [1, 2, 3])
    }

    @Test func workingOnTheBottomAlsoMovesTheUpperPRs() {
        let b = board(workingOn: "feat/a")
        #expect(task(b, 2)?.stack?.workingVia == 1)
        #expect(task(b, 3)?.column == .working)
    }

    @Test func idleStackOnlyLetsTheBottomBeReady() {
        let b = board(workingOn: nil)
        #expect(task(b, 1)?.column == .ready)
        #expect(task(b, 1)?.stack?.base == nil)
        #expect(task(b, 2)?.column == .inReview)
        #expect(task(b, 2)?.reviewReason == .stacked)
        #expect(task(b, 2)?.stack?.base == 1)
        #expect(task(b, 3)?.stack?.base == 2)
    }

    @Test func baseOwnedBySomeoneElseStillBlocksReady() {
        // feat/x targets an open PR that has no session on this board.
        var session = AgentSession.make(id: "s", branch: "feat/x")
        session.turn = .ended
        let prs = [pr(10, "feat/x", base: "feat/teammate"), pr(9, "feat/teammate", base: "main")]
        let b = BoardBuilder.build(sessions: [session], repos: [session.id: orbit], pullRequests: ["acme/orbit": prs],
                                   settings: BoardSettings(), now: testNow)
        #expect(b.tasks.first?.reviewReason == .stacked)
        #expect(b.tasks.first?.stack?.members == [9, 10])
    }

    @Test func mergedBasesAndForksDontFormStacks() {
        var session = AgentSession.make(id: "s", branch: "feat/y")
        session.turn = .ended
        let prs = [pr(20, "feat/y", base: "feat/old"), pr(19, "feat/old", base: "main", state: .merged),
                   pr(21, "feat/z", base: "feat/y", crossRepo: true)]
        let b = BoardBuilder.build(sessions: [session], repos: [session.id: orbit], pullRequests: ["acme/orbit": prs],
                                   settings: BoardSettings(), now: testNow)
        #expect(b.tasks.first?.column == .ready)
        #expect(b.tasks.first?.stack == nil)
    }

    @Test func unrelatedOpenPRsOfARunningSessionStayPut() {
        // The session opened #31 earlier and now works on an unrelated branch: no stack, no spill-over.
        var session = AgentSession.make(id: "s", branch: "feat/new", lastActivity: testNow.addingTimeInterval(-30), turn: .running)
        session.linkedPullRequests = [LinkedPullRequest(repo: orbit.id, branch: "feat/old-fix", number: 31)]
        let b = BoardBuilder.build(sessions: [session], repos: [session.id: orbit],
                                   pullRequests: ["acme/orbit": [pr(31, "feat/old-fix", base: "main")]],
                                   settings: BoardSettings(), now: testNow)
        #expect(task(b, 31)?.column == .ready)
    }

    @Test func failingCIInAnIdleStackKeepsItsReason() {
        var failing = pr(2, "feat/b", base: "feat/a")
        failing.checks = CheckSummary(passed: 1, failed: 1)
        var session = AgentSession.make(id: "s", branch: "feat/b")
        session.turn = .ended
        let b = BoardBuilder.build(sessions: [session], repos: [session.id: orbit],
                                   pullRequests: ["acme/orbit": [pr(1, "feat/a", base: "main"), failing]],
                                   settings: BoardSettings(), now: testNow)
        #expect(task(b, 2)?.reviewReason == .ciFailing)
        #expect(task(b, 2)?.stack?.base == 1)
    }
}
