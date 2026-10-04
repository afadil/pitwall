import Foundation
import Testing
@testable import PitwallCore

/// Write actions (mark ready, merge) must reach `gh` only through a confirmed
/// pending write, and every test here uses the fake `gh`.
@Suite("Write actions need confirmation")
@MainActor
struct WriteActionTests {
    private let openPR = PullRequest.make(42, branch: "feat/offline-sync", review: .approved)
    private let draftPR = PullRequest.make(39, branch: "feat/dark-mode", draft: true)

    private func fakeGH() throws -> FakeGH {
        let gh = FakeGH()
        try gh.respond(to: ["repo", "view"], json: "github/repo-view-acme-orbit.json")
        gh.respond(to: ["pr", "merge"], with: ProcessResult(exitCode: 0))
        gh.respond(to: ["pr", "ready"], with: ProcessResult(exitCode: 0))
        return gh
    }

    @Test func requestingAMergeOnlyPreparesIt() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.merge(.merge), for: openPR)

        #expect(gh.writeCalls.isEmpty)
        // The only call was the read-only lookup of allowed merge methods.
        #expect(gh.recorded == [["repo", "view", "acme/orbit", "--json", "squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed"]])
        let pending = try #require(coordinator.pending)
        #expect(pending.pullRequest.number == 42)
        #expect(pending.allowedMethods == [.squash, .rebase])
        // "merge" isn't allowed in this repo, so the first allowed method is chosen.
        #expect(pending.action == .merge(.squash))
    }

    @Test func cancellingNeverCallsGH() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.merge(.squash), for: openPR)
        coordinator.cancel()
        #expect(coordinator.pending == nil)
        await coordinator.confirm() // nothing pending: no-op
        #expect(gh.writeCalls.isEmpty)
    }

    @Test func confirmingMergeRunsExactlyOneGHMerge() async throws {
        let gh = try fakeGH()
        var refreshed = 0
        let coordinator = WriteActionCoordinator(runner: gh) { refreshed += 1 }
        await coordinator.request(.merge(.squash), for: openPR)
        coordinator.choose(.rebase)
        await coordinator.confirm()

        #expect(gh.writeCalls == [["pr", "merge", "42", "--repo", "acme/orbit", "--rebase", "--match-head-commit", "sha42"]])
        #expect(coordinator.pending == nil)
        #expect(coordinator.lastOutcome == .succeeded("Pull request #42 merged."))
        #expect(refreshed == 1)
    }

    @Test func confirmingMarkReadyRunsGHReady() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.markReady, for: draftPR)
        #expect(gh.recorded.isEmpty) // mark ready needs no lookup at all
        await coordinator.confirm()
        #expect(gh.writeCalls == [["pr", "ready", "39", "--repo", "acme/orbit"]])
    }

    @Test func writerRefusesWithoutConfirmation() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.merge(.squash), for: openPR)
        let pending = try #require(coordinator.pending)

        let writer = GitHubWriter(runner: gh)
        await #expect(throws: WriteError.notConfirmed) {
            try await writer.perform(pending, confirmation: nil)
        }
        #expect(gh.writeCalls.isEmpty)
    }

    @Test func confirmationIsTiedToOnePendingWrite() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.markReady, for: draftPR)
        let first = try #require(coordinator.pending)
        coordinator.cancel()
        await coordinator.request(.merge(.squash), for: openPR)
        let second = try #require(coordinator.pending)
        #expect(first.id != second.id)
        // Confirming runs only the write currently pending, never an earlier one.
        await coordinator.confirm()
        #expect(gh.writeCalls.count == 1)
        #expect(gh.writeCalls.first?.prefix(2) == ["pr", "merge"])
    }

    @Test func inapplicableActionsAreRejectedUpFront() async throws {
        let gh = try fakeGH()
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.merge(.squash), for: draftPR)
        #expect(coordinator.pending == nil)
        #expect(coordinator.lastOutcome == .failed("Pull request #39 is a draft. Mark it ready first."))

        await coordinator.request(.markReady, for: openPR)
        #expect(coordinator.pending == nil)

        let merged = PullRequest.make(40, branch: "fix/x", state: .merged, finished: testNow)
        await coordinator.request(.merge(.squash), for: merged)
        #expect(coordinator.pending == nil)
        #expect(gh.recorded.isEmpty)
    }

    @Test func ghFailureIsReportedAndClearsTheSheet() async throws {
        let gh = try fakeGH()
        gh.respond(to: ["pr", "merge"], with: ProcessResult(exitCode: 1, stderr: Data("Pull request is not mergeable: the base branch policy prohibits the merge.".utf8)))
        let coordinator = WriteActionCoordinator(runner: gh)
        await coordinator.request(.merge(.squash), for: openPR)
        await coordinator.confirm()
        #expect(coordinator.pending == nil)
        #expect(coordinator.lastOutcome == .failed("Pull request is not mergeable: the base branch policy prohibits the merge."))
    }

    @Test func refreshingTheBoardNeverWrites() async throws {
        let home = try FixtureHome()
        defer { withExtendedLifetime(home) {} }
        try home.installClaude()
        try home.installCodex()
        let gh = FakeGH()
        try gh.respond(to: ["pr", "list", "--repo", "acme/orbit"], json: "github/pr-list-acme-orbit.json")
        try gh.respond(to: ["pr", "list", "--repo", "acme/lumen"], json: "github/pr-list-acme-lumen.json")
        let engine = RefreshEngine(paths: home.paths, git: FakeGit([:]), gh: gh)
        let local = await engine.readLocal(now: testNow, calendar: utcCalendar)
        _ = await engine.fetchGitHub(slugs: local.githubSlugs(settings: BoardSettings()), now: testNow)
        #expect(!gh.recorded.isEmpty)
        #expect(gh.writeCalls.isEmpty)
        #expect(gh.recorded.allSatisfy { $0.prefix(2) == ["pr", "list"] })
    }
}
