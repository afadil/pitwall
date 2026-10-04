import Foundation

/// Groups sessions into tasks and places each task in a column.
public enum BoardBuilder {
    private struct Group {
        var repo: ResolvedRepo?
        var branch: String?
        var isDefault: Bool
        /// Sessions currently on this branch.
        var onBranch: [AgentSession] = []
        /// Sessions linked only through a PR the app recorded for them.
        var linked: [AgentSession] = []
        var linkedNumbers: Set<Int> = []
    }

    public static func build(
        sessions: [AgentSession],
        repos: [String: ResolvedRepo],
        pullRequests: [String: [PullRequest]],
        settings: BoardSettings,
        now: Date
    ) -> Board {
        var groups: [String: Group] = [:]
        var allRepos: Set<RepoID> = []

        for session in sessions {
            if session.isArchived, !settings.showArchived { continue }
            let resolved = repos[session.id]
            if let resolved { allRepos.insert(resolved.id) }

            let primaryKey = taskID(for: session, repo: resolved)
            if resolved.map({ !settings.excludedRepos.contains($0.id.key) }) ?? true {
                let branch = session.branch.flatMap { $0.isEmpty ? nil : $0 }
                let isDefault = branch.map { resolved?.isDefaultBranch($0) ?? false } ?? false
                groups[primaryKey, default: Group(repo: resolved, branch: branch, isDefault: isDefault)].onBranch.append(session)
            }

            for link in session.linkedPullRequests {
                allRepos.insert(link.repo)
                guard !settings.excludedRepos.contains(link.repo.key) else { continue }
                let repo = resolved.flatMap { $0.id == link.repo || $0.upstream == link.repo ? $0 : nil }
                    ?? ResolvedRepo(id: link.repo, defaultBranch: knownDefaultBranch(link.repo, in: repos))
                guard !repo.isDefaultBranch(link.branch) else { continue }
                let key = "\(repo.id.key)#\(link.branch)"
                guard key != primaryKey else { continue }
                var group = groups[key, default: Group(repo: repo, branch: link.branch, isDefault: false)]
                if !group.linked.contains(where: { $0.id == session.id }) { group.linked.append(session) }
                if let number = link.number { group.linkedNumbers.insert(number) }
                groups[key] = group
            }
        }

        var tasks: [BoardTask] = []
        for (id, group) in groups {
            let byRecency: (AgentSession, AgentSession) -> Bool = { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
            let onBranch = group.onBranch.sorted(by: byRecency)
            let linked = group.linked.filter { s in !onBranch.contains { $0.id == s.id } }.sorted(by: byRecency)

            var pr: PullRequest?
            if let repo = group.repo, let branch = group.branch, !group.isDefault {
                let candidates = repo.pullRequestSources.flatMap { pullRequests[$0] ?? [] }
                pr = PRMatcher.match(branch: branch, repo: repo, in: candidates)
                    ?? candidates.first { group.linkedNumbers.contains($0.number) && $0.headRefName == branch }
            }
            // A PR link is only worth a card when the PR itself is known.
            if onBranch.isEmpty, pr == nil { continue }

            guard let placement = BoardRules.placement(sessions: onBranch, pullRequest: pr, now: now) else { continue }
            let hidden = settings.hiddenTaskIDs.contains(id)
            if hidden, !settings.showHidden { continue }
            tasks.append(BoardTask(
                id: id,
                repo: group.repo?.id,
                branch: group.branch,
                isDefaultBranch: group.isDefault,
                sessions: onBranch + linked,
                linkedSessionIDs: Set(linked.map(\.id)),
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

    private static func knownDefaultBranch(_ repo: RepoID, in repos: [String: ResolvedRepo]) -> String? {
        repos.values.first { $0.id == repo }?.defaultBranch
    }
}
