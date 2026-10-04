import Foundation

/// Read-only GitHub queries through `gh`.
public struct GitHubClient: Sendable {
    public let runner: GHRunning

    public static let pullRequestFields = [
        "number", "title", "url", "headRefName", "headRefOid", "baseRefName", "state", "isDraft",
        "reviewDecision", "statusCheckRollup", "mergedAt", "closedAt", "updatedAt",
        "isCrossRepository", "headRepositoryOwner", "labels",
    ].joined(separator: ",")

    public init(runner: GHRunning) {
        self.runner = runner
    }

    /// The 100 most recently updated pull requests in any state, plus every open
    /// one (up to 200).
    ///
    /// Two read-only calls per repo, run in parallel. Sorting by update catches old
    /// PRs merged or closed this week; the open list catches old PRs still in review.
    public func pullRequests(repo slug: String) async throws -> [PullRequest] {
        async let recent = list(slug, state: "all", limit: 100, search: "sort:updated-desc")
        async let open = list(slug, state: "open", limit: 200)
        let results = await (recent, open)
        switch results {
        case (.success(let recent), .success(let open)):
            var byNumber = Dictionary(recent.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
            for pr in open { byNumber[pr.number] = pr }
            return byNumber.values.sorted { $0.number > $1.number }
        case (.success(let prs), .failure), (.failure, .success(let prs)):
            return prs
        case (.failure(let error), .failure):
            throw error
        }
    }

    private func list(_ slug: String, state: String, limit: Int, search: String? = nil) async -> Result<[PullRequest], GHError> {
        do {
            var arguments = ["pr", "list", "--repo", slug, "--state", state, "--limit", String(limit)]
            if let search { arguments += ["--search", search] }
            let result = try await runner.run(arguments + ["--json", Self.pullRequestFields])
            guard result.exitCode == 0 else { return .failure(GHError.from(result)) }
            return .success(try PRParsing.pullRequests(from: result.stdout, repo: slug))
        } catch let error as GHError {
            return .failure(error)
        } catch {
            return .failure(.failed(exitCode: -1, message: error.localizedDescription))
        }
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
