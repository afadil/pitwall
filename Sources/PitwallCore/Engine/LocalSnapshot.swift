import Foundation

/// Sessions read from disk plus what git said about their folders.
public struct LocalSnapshot: Sendable {
    public var sessions: [AgentSession]
    /// Session id → repository.
    public var repos: [String: ResolvedRepo]
    public var statuses: [SourceStatus]
    public var readAt: Date

    public init(sessions: [AgentSession] = [], repos: [String: ResolvedRepo] = [:], statuses: [SourceStatus] = [], readAt: Date = .distantPast) {
        self.sessions = sessions
        self.repos = repos
        self.statuses = statuses
        self.readAt = readAt
    }

    public static let empty = LocalSnapshot()

    /// GitHub repositories worth polling: those with sessions on a non-default branch.
    public func githubSlugs(settings: BoardSettings) -> [String] {
        var slugs = Set<String>()
        for session in sessions {
            if session.isArchived, !settings.showArchived { continue }
            for link in session.linkedPullRequests where !settings.excludedRepos.contains(link.repo.key) {
                if let slug = link.repo.githubSlug { slugs.insert(slug) }
            }
            guard let repo = repos[session.id], !settings.excludedRepos.contains(repo.id.key),
                  let branch = session.branch, !repo.isDefaultBranch(branch) else { continue }
            slugs.formUnion(repo.pullRequestSources)
        }
        return slugs.sorted()
    }
}
