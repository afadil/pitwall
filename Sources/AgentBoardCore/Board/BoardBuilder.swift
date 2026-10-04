import Foundation

/// Groups sessions into tasks and places each task in a column.
public enum BoardBuilder {
    public static func build(
        sessions: [AgentSession],
        repos: [String: ResolvedRepo],
        pullRequests: [String: [PullRequest]],
        settings: BoardSettings,
        now: Date
    ) -> Board {
        var groups: [String: (repo: ResolvedRepo?, branch: String?, isDefault: Bool, sessions: [AgentSession])] = [:]
        var allRepos: Set<RepoID> = []

        for session in sessions {
            if session.isArchived, !settings.showArchived { continue }
            let resolved = repos[session.id]
            if let resolved { allRepos.insert(resolved.id) }
            if let resolved, settings.excludedRepos.contains(resolved.id.key) { continue }

            let key = taskID(for: session, repo: resolved)
            let branch = session.branch.flatMap { $0.isEmpty ? nil : $0 }
            let isDefault = branch.map { resolved?.isDefaultBranch($0) ?? false } ?? false
            groups[key, default: (resolved, branch, isDefault, [])].sessions.append(session)
        }

        var tasks: [BoardTask] = []
        for (id, group) in groups {
            let sorted = group.sessions.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
            var pr: PullRequest?
            if let repo = group.repo, let branch = group.branch, !group.isDefault {
                let candidates = repo.pullRequestSources.flatMap { pullRequests[$0] ?? [] }
                pr = PRMatcher.match(branch: branch, repo: repo, in: candidates)
            }
            guard let placement = BoardRules.placement(sessions: sorted, pullRequest: pr, now: now) else { continue }
            let hidden = settings.hiddenTaskIDs.contains(id)
            if hidden, !settings.showHidden { continue }
            tasks.append(BoardTask(
                id: id,
                repo: group.repo?.id,
                branch: group.branch,
                isDefaultBranch: group.isDefault,
                sessions: sorted,
                pullRequest: pr,
                column: placement.column,
                reviewReason: placement.reason,
                isHidden: hidden
            ))
        }

        tasks.sort { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            return lhs.id < rhs.id
        }
        return Board(tasks: tasks, repos: allRepos.sorted(), generatedAt: now)
    }

    /// One card per (repo, branch). Sessions on the default branch, with no
    /// branch, or outside any repo get their own card.
    public static func taskID(for session: AgentSession, repo: ResolvedRepo?) -> String {
        guard let branch = session.branch, !branch.isEmpty,
              let repo, !repo.isDefaultBranch(branch) else {
            return "session:\(session.id)"
        }
        return "\(repo.id.key)#\(branch)"
    }
}
