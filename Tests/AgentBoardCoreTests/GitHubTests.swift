import Foundation
import Testing
@testable import AgentBoardCore

@Suite("gh JSON parsing")
struct GHParsingTests {
    private func orbitPRs() throws -> [PullRequest] {
        try PRParsing.pullRequests(from: Fixtures.data("github/pr-list-acme-orbit.json"), repo: "acme/orbit")
    }

    @Test func parsesTheFixtureAndDropsBrokenEntries() throws {
        let prs = try orbitPRs()
        // 13 entries; "number": "oops" and the one without number/branch are dropped.
        #expect(prs.count == 11)
        #expect(Set(prs.map(\.repo)) == ["acme/orbit"])
    }

    @Test func mapsFieldsOfAnOpenPR() throws {
        let pr = try #require(try orbitPRs().first { $0.number == 42 })
        #expect(pr.title == "feat(sync): queue offline edits")
        #expect(pr.url?.absoluteString == "https://github.com/acme/orbit/pull/42")
        #expect(pr.headRefName == "feat/offline-sync")
        #expect(pr.headRefOid == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(pr.baseRefName == "main")
        #expect(pr.state == .open)
        #expect(!pr.isDraft)
        #expect(pr.reviewDecision == .approved)
        #expect(pr.mergedAt == nil)
        #expect(pr.updatedAt == date("2026-10-04T14:31:00Z"))
        #expect(pr.headOwner == "acme")
        #expect(!pr.isCrossRepository)
    }

    @Test func rerunChecksKeepOnlyTheLatestRun() throws {
        let pr = try #require(try orbitPRs().first { $0.number == 42 })
        // lint ✓, test (macos) cancelled then re-run ✓, deploy preview skipped.
        #expect(pr.checks == CheckSummary(passed: 2, failed: 0, pending: 0, skipped: 1))
        #expect(pr.checks.state == .passing)
    }

    @Test func checkRunAndStatusContextOutcomes() throws {
        let prs = try orbitPRs()
        #expect(prs.first { $0.number == 35 }?.checks.state == .failing)
        #expect(prs.first { $0.number == 33 }?.checks == CheckSummary(pending: 2)) // IN_PROGRESS + PENDING context
        #expect(prs.first { $0.number == 32 }?.checks.state == .passing) // SUCCESS context
        #expect(prs.first { $0.number == 41 }?.checks.state == CIState.none)
    }

    @Test func statesReviewsAndZeroDates() throws {
        let prs = try orbitPRs()
        #expect(prs.first { $0.number == 40 }?.state == .merged)
        #expect(prs.first { $0.number == 40 }?.finishedAt == date("2026-10-03T18:00:00Z"))
        #expect(prs.first { $0.number == 41 }?.state == .closed)
        #expect(prs.first { $0.number == 39 }?.isDraft == true)
        #expect(prs.first { $0.number == 34 }?.reviewDecision == .changesRequested)
        #expect(prs.first { $0.number == 32 }?.reviewDecision == .reviewRequired)
        #expect(prs.first { $0.number == 41 }?.reviewDecision == ReviewDecision.none) // ""
        #expect(prs.first { $0.number == 33 }?.mergedAt == nil) // "0001-01-01T00:00:00Z"
        #expect(prs.first { $0.number == 37 }?.isCrossRepository == true)
        #expect(prs.first { $0.number == 37 }?.headOwner == "someone-else")
    }

    @Test func notAnArrayIsACantReadError() {
        #expect(throws: GHError.unreadableOutput("expected a JSON array of pull requests")) {
            try PRParsing.pullRequests(from: Data("{\"message\":\"Not Found\"}".utf8), repo: "acme/orbit")
        }
        #expect(throws: GHError.self) {
            try PRParsing.pullRequests(from: Data("<html>".utf8), repo: "acme/orbit")
        }
    }

    @Test func emptyListIsFine() throws {
        #expect(try PRParsing.pullRequests(from: Data("[]".utf8), repo: "acme/orbit").isEmpty)
    }

    @Test func classifiesGHFailures() {
        #expect(GHError.from(ProcessResult(exitCode: 4, stderr: Data("To get started with GitHub CLI, please run:  gh auth login".utf8))) == .notSignedIn)
        #expect(GHError.from(ProcessResult(exitCode: 1, stderr: Data("You are not logged into any GitHub hosts. Run gh auth login to authenticate.".utf8))) == .notSignedIn)
        #expect(GHError.from(ProcessResult(exitCode: 1, stderr: Data("GraphQL: Could not resolve to a Repository\nmore".utf8)))
            == .failed(exitCode: 1, message: "GraphQL: Could not resolve to a Repository"))
    }

    @Test func listUsesOneReadOnlyCallPerRepo() async throws {
        let gh = FakeGH()
        try gh.respond(to: ["pr", "list"], json: "github/pr-list-acme-orbit.json")
        let prs = try await GitHubClient(runner: gh).pullRequests(repo: "acme/orbit")
        #expect(prs.count == 11)
        #expect(gh.recorded == [[
            "pr", "list", "--repo", "acme/orbit", "--state", "all", "--limit", "100", "--json",
            "number,title,url,headRefName,headRefOid,baseRefName,state,isDraft,reviewDecision,statusCheckRollup,mergedAt,closedAt,updatedAt,isCrossRepository,headRepositoryOwner",
        ]])
    }

    @Test func signedOutGHIsReported() async {
        let gh = FakeGH()
        gh.respond(to: ["pr", "list"], with: ProcessResult(exitCode: 4, stderr: Data("gh auth login".utf8)))
        await #expect(throws: GHError.notSignedIn) {
            try await GitHubClient(runner: gh).pullRequests(repo: "acme/orbit")
        }
        let snapshot = GitHubSnapshot(errors: ["acme/orbit": .notSignedIn], fetchedAt: testNow)
        #expect(snapshot.status(repoCount: 1).health == .error)
        #expect(snapshot.status(repoCount: 1).detail.contains("gh auth login"))
    }

    @Test func missingGHIsReported() async {
        await #expect(throws: GHError.notInstalled) {
            try await GHCLI(executable: nil).run(["pr", "list"])
        }
        #expect(GitHubSnapshot(errors: ["acme/orbit": .notInstalled], fetchedAt: testNow).status(repoCount: 1).health == .missing)
    }
}

@Suite("Pull request matching")
struct PRMatchingTests {
    private func orbitPRs() throws -> [PullRequest] {
        try PRParsing.pullRequests(from: Fixtures.data("github/pr-list-acme-orbit.json"), repo: "acme/orbit")
    }

    @Test func matchesByHeadBranchPreferringOpen() throws {
        // #42 (open), #41 (closed) and #37 (someone else's fork) all use feat/offline-sync.
        let pr = PRMatcher.match(branch: "feat/offline-sync", repo: orbit, in: try orbitPRs())
        #expect(pr?.number == 42)
    }

    @Test func otherPeoplesForksNeverMatch() throws {
        let prs = try orbitPRs().filter { $0.number != 42 }
        // Only the closed #41 remains from our repo; the fork's open #37 must not win.
        #expect(PRMatcher.match(branch: "feat/offline-sync", repo: orbit, in: prs)?.number == 41)
    }

    @Test func forkCheckoutMatchesItsPRUpstream() {
        // Local clone of me/orbit with upstream acme/orbit; the PR lives upstream.
        let fork = ResolvedRepo(id: RepoID(host: "github.com", owner: "me", name: "orbit"),
                                upstream: RepoID(host: "github.com", owner: "acme", name: "orbit"))
        let upstreamPR = PullRequest.make(9, repo: "acme/orbit", branch: "feat/x", crossRepo: true, headOwner: "me")
        let stranger = PullRequest.make(10, repo: "acme/orbit", branch: "feat/x", crossRepo: true, headOwner: "stranger")
        #expect(PRMatcher.match(branch: "feat/x", repo: fork, in: [stranger, upstreamPR])?.number == 9)
        #expect(PRMatcher.match(branch: "feat/x", repo: fork, in: [stranger]) == nil)
    }

    @Test func newestFinishedWhenNothingIsOpen() {
        let older = PullRequest.make(1, branch: "feat/x", state: .closed, finished: testNow.addingTimeInterval(-7200))
        let newer = PullRequest.make(2, branch: "feat/x", state: .merged, finished: testNow.addingTimeInterval(-60))
        #expect(PRMatcher.match(branch: "feat/x", repo: orbit, in: [newer, older])?.number == 2)
    }

    @Test func branchWithoutAPullRequest() throws {
        #expect(PRMatcher.match(branch: "feat/never-pushed", repo: orbit, in: try orbitPRs()) == nil)
    }

    @Test func nonGitHubReposAreNotMatched() {
        let local = ResolvedRepo(id: .local(path: "/Users/dev/work/agent-board"))
        #expect(PRMatcher.match(branch: "feat/x", repo: local, in: [.make(1, branch: "feat/x")]) == nil)
    }

    @Test func branchNamesAreCaseSensitive() {
        #expect(PRMatcher.match(branch: "Feat/X", repo: orbit, in: [.make(1, branch: "feat/x")]) == nil)
    }
}
