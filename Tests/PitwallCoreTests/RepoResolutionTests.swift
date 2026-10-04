import Foundation
import Testing
@testable import PitwallCore

@Suite("Branch and repo resolution")
struct RepoResolutionTests {
    @Test(arguments: [
        ("https://github.com/acme/orbit.git", "github.com/acme/orbit"),
        ("https://github.com/acme/orbit", "github.com/acme/orbit"),
        ("https://github.com/acme/orbit/", "github.com/acme/orbit"),
        ("git@github.com:acme/orbit.git", "github.com/acme/orbit"),
        ("ssh://git@github.com/acme/orbit.git", "github.com/acme/orbit"),
        ("ssh://git@github.com:22/acme/orbit", "github.com/acme/orbit"),
        ("https://token-free-user@github.com/Acme/Orbit.git", "github.com/acme/orbit"),
        ("https://www.github.com/acme/orbit", "github.com/acme/orbit"),
        ("https://gitlab.example.com/group/sub/proj.git", "gitlab.example.com/group/sub/proj"),
    ])
    func normalisesRemoteURLs(remote: String, key: String) throws {
        let repo = try #require(RepoID.fromRemote(remote))
        #expect(repo.key == key)
    }

    @Test func githubSlugOnlyForGitHub() throws {
        #expect(RepoID.fromRemote("git@github.com:acme/orbit.git")?.githubSlug == "acme/orbit")
        #expect(RepoID.fromRemote("https://gitlab.example.com/acme/orbit")?.githubSlug == nil)
        #expect(RepoID.local(path: "/Users/dev/work/agent-board").githubSlug == nil)
        #expect(RepoID.local(path: "/Users/dev/work/agent-board").displayName == "agent-board")
    }

    @Test(arguments: ["", "not a url", "/local/path/only", "https://github.com/onlyowner", "file:///tmp/repo"])
    func rejectsUnusableRemotes(remote: String) {
        #expect(RepoID.fromRemote(remote) == nil)
    }

    @Test func parsesGitOutput() {
        let remotes = RepoResolver.parseRemotes("remote.origin.url https://github.com/me/orbit.git\nremote.upstream.url git@github.com:acme/orbit.git\njunk line\n")
        #expect(remotes == ["origin": "https://github.com/me/orbit.git", "upstream": "git@github.com:acme/orbit.git"])
        #expect(RepoResolver.parseDefaultBranch("origin/main\n") == "main")
        #expect(RepoResolver.parseDefaultBranch("origin/release/2026\n") == "release/2026")
        #expect(RepoResolver.parseDefaultBranch("") == nil)
    }

    @Test func resolvesOriginUpstreamAndDefaultBranch() async throws {
        let home = try FixtureHome()
        let dir = home.url.path
        let git = FakeGit([dir: .init(remotes: ["origin": "git@github.com:me/orbit.git", "upstream": "https://github.com/acme/orbit"], defaultBranch: "origin/trunk")])
        let resolver = RepoResolver(git: git)
        let resolved = try #require(await resolver.resolve(.make(id: "s1", cwd: dir, branch: "feat/x")))
        #expect(resolved.id.key == "github.com/me/orbit")
        #expect(resolved.upstream?.key == "github.com/acme/orbit")
        #expect(resolved.defaultBranch == "trunk")
        #expect(resolved.pullRequestSources == ["me/orbit", "acme/orbit"])
        #expect(resolved.isDefaultBranch("trunk"))
        #expect(!resolved.isDefaultBranch("main"))
    }

    @Test func fallsBackToGitRootsWhenTheWorktreeIsGone() async throws {
        let home = try FixtureHome()
        let root = home.url.path
        let git = FakeGit([root: .init(remotes: ["origin": "https://github.com/acme/orbit.git"])])
        var session = AgentSession.make(id: "s1", cwd: "/nonexistent/worktree", branch: "feat/x")
        session.fallbackDirectories = [root]
        let resolved = await RepoResolver(git: git).resolve(session)
        #expect(resolved?.id.key == "github.com/acme/orbit")
        #expect(git.calls.allSatisfy { $0.directory == root })
    }

    @Test func checkoutWithoutRemoteUsesItsMainFolder() async throws {
        let home = try FixtureHome()
        let worktree = home.url.appending(path: "repo/.claude/worktrees/wt").path
        try FileManager.default.createDirectory(atPath: worktree, withIntermediateDirectories: true)
        let git = FakeGit([worktree: .init(remotes: [:], defaultBranch: nil, commonDir: home.url.appending(path: "repo/.git").path)])
        let resolved = await RepoResolver(git: git).resolve(.make(id: "s1", cwd: worktree, branch: "claude/wt"))
        #expect(resolved?.id == .local(path: home.url.appending(path: "repo").path))
        #expect(resolved?.id.displayName == "repo")
        #expect(resolved?.isDefaultBranch("main") == true)
    }

    @Test func codexOriginURLWorksWithoutAnyCheckout() async {
        let git = FakeGit([:])
        var session = AgentSession.make(.codex, id: "t1", cwd: "/nonexistent/codex/worktree", branch: "codex/fix")
        session.originURL = "https://github.com/acme/lumen.git"
        let resolved = await RepoResolver(git: git).resolve(session)
        #expect(resolved?.id.githubSlug == "acme/lumen")
        #expect(git.callCount == 0)
    }

    @Test func noRepositoryAtAll() async {
        let resolved = await RepoResolver(git: FakeGit([:])).resolve(.make(id: "s1", cwd: "/nonexistent/folder", branch: nil))
        #expect(resolved == nil)
    }

    @Test func cachesLookupsPerFolder() async throws {
        let home = try FixtureHome()
        let dir = home.url.path
        let git = FakeGit([dir: .init(remotes: ["origin": "https://github.com/acme/orbit.git"])])
        let resolver = RepoResolver(git: git)
        _ = await resolver.resolve(.make(id: "a", cwd: dir, branch: "x"), now: testNow)
        let first = git.callCount
        _ = await resolver.resolve(.make(id: "b", cwd: dir, branch: "y"), now: testNow.addingTimeInterval(60))
        #expect(git.callCount == first)
        _ = await resolver.resolve(.make(id: "c", cwd: dir, branch: "z"), now: testNow.addingTimeInterval(3600))
        #expect(git.callCount > first)
    }

    @Test func gitCommandsAreReadOnly() async throws {
        let home = try FixtureHome()
        let dir = home.url.path
        let git = FakeGit([dir: .init(remotes: [:], defaultBranch: nil, commonDir: dir + "/.git")])
        _ = await RepoResolver(git: git).resolve(.make(id: "a", cwd: dir, branch: "x"))
        let readOnly: Set<String> = ["config", "symbolic-ref", "rev-parse"]
        #expect(git.calls.allSatisfy { readOnly.contains($0.arguments.first ?? "") })
        #expect(git.calls.first { $0.arguments.first == "config" }?.arguments.contains("--get-regexp") == true)
    }
}
