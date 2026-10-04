import Foundation

/// Read-only GitHub queries through `gh`.
public struct GitHubClient: Sendable {
    public let runner: GHRunning

    public static let pullRequestFields = [
        "number", "title", "url", "headRefName", "headRefOid", "baseRefName", "state", "isDraft",
        "reviewDecision", "statusCheckRollup", "mergedAt", "closedAt", "updatedAt",
        "isCrossRepository", "headRepositoryOwner",
    ].joined(separator: ",")

    public init(runner: GHRunning) {
        self.runner = runner
    }

    /// One call per repo: the newest 100 pull requests in any state.
    public func pullRequests(repo slug: String) async throws -> [PullRequest] {
        let result = try await runner.run([
            "pr", "list", "--repo", slug, "--state", "all", "--limit", "100",
            "--json", Self.pullRequestFields,
        ])
        guard result.exitCode == 0 else { throw GHError.from(result) }
        return try PRParsing.pullRequests(from: result.stdout, repo: slug)
    }

    /// Merge methods the repository allows, for the merge confirmation sheet.
    public func mergeMethods(repo slug: String) async throws -> [MergeMethod] {
        let result = try await runner.run([
            "repo", "view", slug, "--json", "squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed",
        ])
        guard result.exitCode == 0 else { throw GHError.from(result) }
        guard let object = (try? JSONSerialization.jsonObject(with: result.stdout)) as? [String: Any] else {
            throw GHError.unreadableOutput("expected a JSON object")
        }
        var methods: [MergeMethod] = []
        if object.bool("squashMergeAllowed") == true { methods.append(.squash) }
        if object.bool("mergeCommitAllowed") == true { methods.append(.merge) }
        if object.bool("rebaseMergeAllowed") == true { methods.append(.rebase) }
        return methods.isEmpty ? MergeMethod.allCases : methods
    }
}

/// Result of polling every tracked repository.
public struct GitHubSnapshot: Sendable {
    public var pullRequests: [String: [PullRequest]]
    public var errors: [String: GHError]
    public var fetchedAt: Date?

    public init(pullRequests: [String: [PullRequest]] = [:], errors: [String: GHError] = [:], fetchedAt: Date? = nil) {
        self.pullRequests = pullRequests
        self.errors = errors
        self.fetchedAt = fetchedAt
    }

    public static let empty = GitHubSnapshot()

    /// Overall status for Settings and the board banner.
    public func status(repoCount: Int) -> SourceStatus {
        let path = "gh pr list"
        if errors.values.contains(.notInstalled) {
            return SourceStatus(kind: .github, path: path, health: .missing, detail: GHError.notInstalled.description)
        }
        if errors.values.contains(.notSignedIn) {
            return SourceStatus(kind: .github, path: path, health: .error, detail: GHError.notSignedIn.description)
        }
        if fetchedAt == nil {
            return SourceStatus(kind: .github, path: path, health: .ok, detail: repoCount == 0 ? "No GitHub repositories yet" : "Loading…")
        }
        if !errors.isEmpty {
            let failed = errors.keys.sorted().joined(separator: ", ")
            let first = errors.values.first.map { " (\($0.description))" } ?? ""
            return SourceStatus(kind: .github, path: path, health: errors.count >= repoCount ? .error : .warning,
                                detail: "Can't read pull requests for \(failed)\(first)")
        }
        return SourceStatus(kind: .github, path: path, health: .ok,
                            detail: "Signed in · \(repoCount) repositor\(repoCount == 1 ? "y" : "ies")")
    }
}

public enum PRMatcher {
    /// The pull request whose head is `branch` in this checkout's repository.
    ///
    /// A same-repo PR must live in the checkout's own repo. A cross-repo PR (from
    /// a fork) only matches when the fork belongs to the checkout's `origin` owner,
    /// so someone else's fork with the same branch name never matches.
    /// Open PRs win; otherwise the most recently finished one.
    public static func match(branch: String, repo: ResolvedRepo, in pullRequests: [PullRequest]) -> PullRequest? {
        guard let originSlug = repo.id.githubSlug?.lowercased() else { return nil }
        let originOwner = repo.id.owner?.lowercased()
        let candidates = pullRequests.filter { pr in
            guard pr.headRefName == branch else { return false }
            if pr.isCrossRepository {
                return pr.headOwner?.lowercased() == originOwner && pr.repo.lowercased() != originSlug
            }
            return pr.repo.lowercased() == originSlug
        }
        if let open = candidates.filter({ $0.state == .open }).max(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }) {
            return open
        }
        return candidates.max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }
}
