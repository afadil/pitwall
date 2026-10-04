import Foundation
import Testing
@testable import AgentBoardCore

@Suite("Board column rules")
struct BoardRulesTests {
    private func place(_ sessions: [AgentSession], _ pr: PullRequest? = nil) -> (BoardColumn, ReviewReason?)? {
        BoardRules.placement(sessions: sessions, pullRequest: pr, now: testNow).map { ($0.column, $0.reason) }
    }

    private let ended = AgentSession.make(id: "s", branch: "feat/x", turn: .ended)

    @Test func runningTurnIsWorking() {
        let s = AgentSession.make(id: "s", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-120), turn: .running)
        #expect(place([s])?.0 == .working)
    }

    @Test func workingBeatsEveryPRState() {
        let s = AgentSession.make(id: "s", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-60), turn: .running)
        #expect(place([s], .make(1, branch: "feat/x", state: .merged, finished: testNow))?.0 == .working)
        #expect(place([s], .make(1, branch: "feat/x", review: .approved))?.0 == .working)
    }

    @Test func stalledTurnIsWaitingOnYou() {
        let s = AgentSession.make(id: "s", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-3600), turn: .running,
                                  lastWrite: testNow.addingTimeInterval(-11 * 60))
        #expect(place([s])?.0 == .waiting)
    }

    @Test func subAgentWritesKeepATurnAlive() {
        let s = AgentSession.make(id: "s", branch: "feat/x", lastActivity: testNow.addingTimeInterval(-30 * 60), turn: .running,
                                  lastWrite: testNow.addingTimeInterval(-60))
        #expect(place([s])?.0 == .working)
    }

    @Test func unknownStateFallsBackToRecentActivity() {
        let recent = AgentSession.make(id: "s", lastActivity: testNow.addingTimeInterval(-60), turn: .unknown)
        let old = AgentSession.make(id: "s", lastActivity: testNow.addingTimeInterval(-600), turn: .unknown)
        #expect(place([recent])?.0 == .working)
        #expect(place([old])?.0 == .waiting)
    }

    @Test func endedTurnWithoutPRIsWaitingOnYou() {
        #expect(place([ended])?.0 == .waiting)
        // Ended turns go straight to "Waiting on you", even moments later.
        let justEnded = AgentSession.make(id: "s", lastActivity: testNow.addingTimeInterval(-5), turn: .ended)
        #expect(place([justEnded])?.0 == .waiting)
    }

    @Test func openPRReasons() {
        #expect(place([ended], .make(1, branch: "feat/x", draft: true))! == (.inReview, .draft))
        #expect(place([ended], .make(1, branch: "feat/x", review: .approved, checks: .init(passed: 3, failed: 1)))! == (.inReview, .ciFailing))
        #expect(place([ended], .make(1, branch: "feat/x", checks: .init(passed: 1, pending: 2)))! == (.inReview, .ciRunning))
        #expect(place([ended], .make(1, branch: "feat/x", review: .changesRequested))! == (.inReview, .changesRequested))
        #expect(place([ended], .make(1, branch: "feat/x", review: .changesRequested, checks: .init(pending: 1)))! == (.inReview, .changesRequested))
        #expect(place([ended], .make(1, branch: "feat/x", review: .reviewRequired))! == (.inReview, .awaitingReview))
    }

    @Test func readyToMergeNeedsGreenCIAndNoBlockingReview() {
        #expect(place([ended], .make(1, branch: "feat/x", review: .approved))! == (.ready, nil))
        #expect(place([ended], .make(1, branch: "feat/x", review: .none))! == (.ready, nil))
        // A repo with no CI at all still counts as green.
        #expect(place([ended], .make(1, branch: "feat/x", review: .approved, checks: .init()))! == (.ready, nil))
        #expect(place([ended], .make(1, branch: "feat/x", checks: .init(passed: 1, skipped: 4)))! == (.ready, nil))
    }

    @Test func finishedPRsAreDoneForAWeekThenLeave() {
        let merged = PullRequest.make(1, branch: "feat/x", state: .merged, finished: testNow.addingTimeInterval(-6 * 86400))
        let closed = PullRequest.make(2, branch: "feat/x", state: .closed, finished: testNow.addingTimeInterval(-86400))
        let old = PullRequest.make(3, branch: "feat/x", state: .merged, finished: testNow.addingTimeInterval(-8 * 86400))
        #expect(place([ended], merged)?.0 == .done)
        #expect(place([ended], closed)?.0 == .done)
        #expect(place([ended], old) == nil)
    }

    @Test func checkSummaryState() {
        #expect(CheckSummary().state == .none)
        #expect(CheckSummary(skipped: 2).state == .passing)
        #expect(CheckSummary(passed: 1, pending: 1).state == .pending)
        #expect(CheckSummary(passed: 5, failed: 1, pending: 1).state == .failing)
    }
}
