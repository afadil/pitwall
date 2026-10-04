import Foundation
import Testing
@testable import PitwallCore

@Suite("Lanes, tags and organization.json")
struct OrganizationTests {
    private let release = CardTag(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, name: "release 4.2", color: .orange)
    private let bug = CardTag(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, name: "bug", color: .red)

    // MARK: Model

    @Test func lanesTagsAndHiddenPerCard() {
        var org = Organization(tags: [release, bug])
        org.setLane(.fast, for: ["t1"], now: testNow)
        org.setTag(bug.id, on: true, for: "t1", now: testNow)
        org.setTag(release.id, on: true, for: "t1", now: testNow)
        org.setHidden(true, for: "t2", now: testNow)

        #expect(org.lane(for: "t1") == .fast)
        #expect(org.tags(for: "t1").map(\.name) == ["release 4.2", "bug"]) // tag-list order, many tags
        #expect(org.isHidden("t2"))
        #expect(org.lane(for: "unknown") == nil)

        org.setTag(bug.id, on: false, for: "t1", now: testNow)
        #expect(org.tags(for: "t1") == [release])
    }

    @Test func emptyEntriesDisappear() {
        var org = Organization(tags: [bug])
        org.setLane(.later, for: ["t1"], now: testNow)
        org.setLane(.normal, for: ["t1"], now: testNow)
        #expect(org.cards["t1"] == nil)
    }

    @Test func creatingTagsDedupesAndCyclesColours() throws {
        var org = Organization()
        let first = org.createTag(named: "  Bug ")
        let again = org.createTag(named: "bug")
        let blank = org.createTag(named: "   ")
        let second = org.createTag(named: "Research")
        let a = try #require(first)
        let b = try #require(second)
        #expect(a.name == "Bug")
        #expect(again?.id == a.id) // same name, any case
        #expect(blank == nil)
        #expect(a.color != b.color)
        #expect(org.tags.count == 2)
    }

    @Test func renameRecolorAndDelete() {
        var org = Organization(tags: [release, bug])
        org.setTag(bug.id, on: true, for: "t1", now: testNow)
        org.renameTag(bug.id, to: "release 4.2") // clash: ignored
        #expect(org.tags[1].name == "bug")
        org.renameTag(bug.id, to: "regression")
        org.recolorTag(bug.id, to: .purple)
        #expect(org.tags[1].name == "regression" && org.tags[1].color == .purple)
        org.deleteTag(bug.id)
        #expect(org.tags == [release])
        #expect(org.cards["t1"] == nil) // the card had nothing else
    }

    @Test func seenCardsAreKeptAndStaleOnesPruned() {
        var org = Organization(tags: [bug])
        org.setTag(bug.id, on: true, for: "old", now: testNow.addingTimeInterval(-40 * 86400))
        org.setTag(bug.id, on: true, for: "recent", now: testNow.addingTimeInterval(-2 * 86400))
        let refreshed = org.markSeen(["recent"], now: testNow) // more than a day old: refresh
        let again = org.markSeen(["recent"], now: testNow.addingTimeInterval(60)) // not again within a day
        let pruned = org.prune(now: testNow)
        #expect(refreshed)
        #expect(!again)
        #expect(pruned)
        #expect(org.cards.keys.sorted() == ["recent"])
    }

    // MARK: Store

    @Test func savesAndLoadsAtomically() throws {
        let home = try FixtureHome()
        let store = OrganizationStore(url: home.url.appending(path: "Pitwall/organization.json"))
        #expect(store.load().isNew)

        var org = Organization(tags: [release, bug])
        org.setLane(.fast, for: ["github.com/acme/orbit#feat/a"], now: testNow)
        org.setTag(release.id, on: true, for: "github.com/acme/orbit#feat/a", now: testNow)
        try store.save(org)

        let loaded = store.load()
        #expect(!loaded.isNew)
        #expect(loaded.problem == nil)
        #expect(loaded.organization == org)
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(text.contains("\"lane\" : \"fast\"")) // readable JSON
    }

    @Test func adoptsTheFileFromBeforeTheRename() throws {
        let home = try FixtureHome()
        try home.write(#"{"version": 1, "tags": [], "cards": {}}"#, to: "Agent Board/organization.json")
        let store = OrganizationStore(url: home.url.appending(path: "Pitwall/organization.json"))
        let legacy = home.url.appending(path: "Agent Board/organization.json")
        #expect(store.adoptLegacyFile(at: legacy))
        #expect(FileManager.default.fileExists(atPath: store.url.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        // Never overwrites an existing file.
        try home.write("{}", to: "Agent Board/organization.json")
        #expect(!store.adoptLegacyFile(at: legacy))
    }

    @Test func unreadableFileIsKeptAsideNotLost() throws {
        let home = try FixtureHome()
        try home.write("{ this is not json", to: "Pitwall/organization.json")
        let store = OrganizationStore(url: home.url.appending(path: "Pitwall/organization.json"))
        let loaded = store.load()
        #expect(loaded.organization == Organization())
        #expect(loaded.problem?.contains("Can't read organization.json") == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: home.url.appending(path: "Pitwall").path)
        #expect(files.contains { $0.hasPrefix("organization.unreadable-") })
    }

    @Test func decodingIsTolerant() throws {
        let json = """
        {"version": 7, "futureField": [1, 2],
         "tags": [{"id": "00000000-0000-0000-0000-00000000000A", "name": "release 4.2", "color": "orange"},
                  {"id": "not-a-uuid", "name": "broken"},
                  {"id": "00000000-0000-0000-0000-00000000000C", "name": "odd colour", "color": "chartreuse"}],
         "cards": {"t1": {"lane": "fast", "tagIDs": ["00000000-0000-0000-0000-00000000000A", "00000000-0000-0000-0000-0000000000FF"],
                          "lastSeen": "2026-10-04T12:00:00Z", "extra": true},
                   "t2": {"lane": "sideways"}}}
        """
        let org = try OrganizationStore.decoder.decode(Organization.self, from: Data(json.utf8))
        #expect(org.tags == [release]) // malformed tags dropped
        #expect(org.lane(for: "t1") == .fast)
        #expect(org.cards["t1"]?.tagIDs == [release.id]) // unknown tag id dropped
        #expect(org.lane(for: "t2") == nil) // unknown lane ignored
    }

    // MARK: Board

    private func session(_ id: String, branch: String) -> AgentSession {
        AgentSession.make(id: id, branch: branch, lastActivity: testNow.addingTimeInterval(-600))
    }

    @Test func builderAppliesLanesTagsAndHidden() {
        let a = session("a", branch: "feat/a"), b = session("b", branch: "feat/b"), c = session("c", branch: "feat/c")
        var org = Organization(tags: [release, bug])
        org.setLane(.fast, for: ["github.com/acme/orbit#feat/a"], now: testNow)
        org.setTag(bug.id, on: true, for: "github.com/acme/orbit#feat/b", now: testNow)
        org.setHidden(true, for: "github.com/acme/orbit#feat/c", now: testNow)
        let board = BoardBuilder.build(sessions: [a, b, c], repos: [a.id: orbit, b.id: orbit, c.id: orbit], pullRequests: [:],
                                       settings: BoardSettings(), organization: org, now: testNow)
        #expect(board.tasks.count == 2)
        #expect(board.tasks.first { $0.branch == "feat/a" }?.lane == .fast)
        #expect(board.tasks.first { $0.branch == "feat/b" }?.tags == [bug])
        #expect(board.tasks.first { $0.branch == "feat/b" }?.lane == .normal)
    }

    @Test func stackedCardsShareTheirStacksLane() {
        var s = session("s", branch: "main")
        s.linkedPullRequests = [LinkedPullRequest(repo: orbit.id, branch: "feat/a", number: 1),
                                LinkedPullRequest(repo: orbit.id, branch: "feat/b", number: 2)]
        var p1 = PullRequest.make(1, branch: "feat/a"); p1.baseRefName = "main"
        var p2 = PullRequest.make(2, branch: "feat/b"); p2.baseRefName = "feat/a"
        var org = Organization()
        org.setLane(.fast, for: ["github.com/acme/orbit#feat/a"], now: testNow) // only the bottom PR was moved
        let board = BoardBuilder.build(sessions: [s], repos: [s.id: orbit], pullRequests: ["acme/orbit": [p1, p2]],
                                       settings: BoardSettings(), organization: org, now: testNow)
        #expect(board.tasks.first { $0.branch == "feat/b" }?.lane == .fast)
        let top = board.tasks.first { $0.branch == "feat/b" }!
        #expect(BoardLayout.stackPeers(of: top, in: board.tasks) == ["github.com/acme/orbit#feat/a", "github.com/acme/orbit#feat/b"])
    }

    @Test func legacyHiddenSettingStillHides() {
        let a = session("a", branch: "feat/a")
        let board = BoardBuilder.build(sessions: [a], repos: [a.id: orbit], pullRequests: [:],
                                       settings: BoardSettings(hiddenTaskIDs: ["github.com/acme/orbit#feat/a"]), now: testNow)
        #expect(board.tasks.isEmpty)
    }

    // MARK: Layout and filter

    private func task(_ branch: String, lane: Lane = .normal, tags: [CardTag] = [], labels: [String] = [], repo: ResolvedRepo? = orbit,
                      column: BoardColumn = .waiting) -> BoardTask {
        var pr: PullRequest?
        if !labels.isEmpty {
            pr = PullRequest.make(branch.count, branch: branch)
            pr?.labels = labels.map { PRLabel(name: $0, color: "d73a4a") }
        }
        return BoardTask(id: branch, repo: repo?.id, branch: branch, isDefaultBranch: false, sessions: [], pullRequest: pr,
                         column: column, reviewReason: nil, lane: lane, tags: tags)
    }

    @Test func laneRowsKeepFastOnTopAndLaterAtTheBottom() {
        let rows = BoardLayout.rows([task("a", lane: .later), task("b"), task("c", lane: .fast)], grouping: .lane, tags: [])
        #expect(rows.map(\.title) == ["Fast lane", "Normal", "Later"])
        #expect(rows.map { $0.tasks.map(\.id) } == [["c"], ["b"], ["a"]])
        #expect(rows[0].dropLane == .fast && rows[2].dropLane == .later)
    }

    @Test func emptyFastLaneAndLaterStayAsDropTargets() {
        let rows = BoardLayout.rows([task("b")], grouping: .lane, tags: [])
        #expect(rows.count == 3)
        #expect(rows[0].tasks.isEmpty && rows[2].tasks.isEmpty)
    }

    @Test func groupingByTagUsesTheFirstTag() {
        let rows = BoardLayout.rows([task("a", tags: [release, bug]), task("b", tags: [bug]), task("c"), task("d", lane: .fast, tags: [bug])],
                                    grouping: .tag, tags: [release, bug])
        #expect(rows.map(\.title) == ["Fast lane", "release 4.2", "bug", "No tag", "Later"])
        #expect(rows[1].tasks.map(\.id) == ["a"])
        #expect(rows[2].tasks.map(\.id) == ["b"])
        #expect(rows[2].dropTag == bug.id && rows[2].dropLane == .normal)
        #expect(rows[0].tasks.map(\.id) == ["d"]) // the fast lane wins over tags
    }

    @Test func groupingByRepository() {
        let rows = BoardLayout.rows([task("a", repo: lumen), task("b"), task("c", repo: nil)], grouping: .repository, tags: [])
        #expect(rows.map(\.title) == ["Fast lane", "acme/lumen", "acme/orbit", "No repository", "Later"])
    }

    @Test func fastLaneLimitIgnoresDone() {
        let rows = BoardLayout.rows([task("a", lane: .fast), task("b", lane: .fast, column: .done)], grouping: .lane, tags: [])
        #expect(rows[0].activeCount == 1)
    }

    @Test func filterByManyTagsAnyOrAll() {
        let both = task("both", tags: [release, bug]), onlyBug = task("bug", tags: [bug]), none = task("none")
        var filter = TagFilter(tagIDs: [release.id, bug.id], mode: .any)
        #expect([both, onlyBug, none].filter(filter.matches).map(\.id) == ["both", "bug"])
        filter.mode = .all
        #expect([both, onlyBug, none].filter(filter.matches).map(\.id) == ["both"])
        #expect(TagFilter().matches(none)) // no filter: everything
    }

    @Test func filterByGitHubLabels() {
        let labelled = task("x", labels: ["Bug", "ui"]), other = task("y", labels: ["docs"])
        var filter = TagFilter()
        filter.toggle(label: "bug")
        #expect([labelled, other].filter(filter.matches).map(\.id) == ["x"])
        filter.toggle(tag: release.id)
        filter.mode = .all
        #expect([labelled, other].filter(filter.matches).isEmpty) // needs the tag too
        #expect(BoardLayout.labels(in: [labelled, other]).map(\.name) == ["Bug", "docs", "ui"])
    }
}
