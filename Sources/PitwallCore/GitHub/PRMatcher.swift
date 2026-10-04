import Foundation

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
        if let open = candidates.filter({ $0.state == .open }).max(by: { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) })
        {
            return open
        }
        return candidates.max { ($0.finishedAt ?? .distantPast) < ($1.finishedAt ?? .distantPast) }
    }
}
