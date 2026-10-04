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
        organization: Organization = Organization(),
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
            // `hiddenTaskIDs` in settings predates organization.json; both still count.
            let hidden = organization.isHidden(id) || settings.hiddenTaskIDs.contains(id)
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

        applyStacks(to: &tasks, pullRequests: pullRequests)
        applyOrganization(organization, to: &tasks)

        tasks.sort { lhs, rhs in
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate > rhs.sortDate }
            return lhs.id < rhs.id
        }
        return Board(tasks: tasks, repos: allRepos.sorted(), generatedAt: now)
    }

    /// PRs that target each other's branches form a stack, and a stack is one piece
    /// of work:
    /// - while a session works on any card in a stack, the stack's other open PRs
    ///   are Working too (agents restack and force-push lower PRs as they go);
    /// - otherwise a PR whose base is another open PR's branch can't land first, so
    ///   it's In review ("Stacked") rather than Ready to merge.
    static func applyStacks(to tasks: inout [BoardTask], pullRequests: [String: [PullRequest]]) {
        // Open same-repo PRs by repo and head branch, from everything gh returned.
        var openByHead: [String: [String: PullRequest]] = [:]
        for (slug, prs) in pullRequests {
            for pr in prs where pr.state == .open && !pr.isCrossRepository {
                openByHead[slug.lowercased(), default: [:]][pr.headRefName] = pr
            }
        }
        func base(of pr: PullRequest) -> PullRequest? {
            guard let baseRef = pr.baseRefName, baseRef != pr.headRefName else { return nil }
            return openByHead[pr.repo.lowercased()]?[baseRef]
        }
        func key(_ pr: PullRequest) -> String { "\(pr.repo.lowercased())#\(pr.number)" }

        // Walk each open PR down to the bottom of its stack, then collect members.
        var bottomOf: [String: String] = [:]
        var prByKey: [String: PullRequest] = [:]
        for prs in openByHead.values {
            for pr in prs.values {
                prByKey[key(pr)] = pr
                var current = pr
                var seen: Set<Int> = [pr.number]
                while let next = base(of: current), seen.insert(next.number).inserted { current = next }
                bottomOf[key(pr)] = key(current)
            }
        }
        var stacks: [String: [PullRequest]] = [:]
        for (member, bottom) in bottomOf { stacks[bottom, default: []].append(prByKey[member]!) }
        func ordered(_ members: [PullRequest]) -> [Int] {
            // Bottom first: sort by distance from the bottom of the stack.
            func depth(_ pr: PullRequest) -> Int {
                var d = 0, current = pr
                var seen: Set<Int> = [pr.number]
                while let next = base(of: current), seen.insert(next.number).inserted { d += 1; current = next }
                return d
            }
            return members.sorted { (depth($0), $0.number) < (depth($1), $1.number) }.map(\.number)
        }

        // Which stacks have a card that is Working on its own account?
        var workingVia: [String: Int] = [:]
        for task in tasks where task.column == .working {
            if let pr = task.pullRequest, pr.state == .open, let bottom = bottomOf[key(pr)] {
                workingVia[bottom] = workingVia[bottom] ?? pr.number
            }
        }

        for index in tasks.indices {
            guard let pr = tasks[index].pullRequest, pr.state == .open,
                  let bottom = bottomOf[key(pr)], let members = stacks[bottom], members.count > 1 else { continue }
            var info = StackInfo(members: ordered(members), base: base(of: pr)?.number)
            if tasks[index].column != .working, let via = workingVia[bottom], via != pr.number {
                tasks[index].column = .working
                tasks[index].reviewReason = nil
                info.workingVia = via
            } else if tasks[index].column == .ready, info.base != nil {
                tasks[index].column = .inReview
                tasks[index].reviewReason = .stacked
            }
            tasks[index].stack = info
        }
    }

    /// Lanes and tags from organization.json. A stacked card without its own lane
    /// takes its stack's (fast first), so a stack moves as one.
    static func applyOrganization(_ organization: Organization, to tasks: inout [BoardTask]) {
        var stackLane: [String: Lane] = [:]
        func stackKey(_ task: BoardTask) -> String? {
            guard let pr = task.pullRequest, let bottom = task.stack?.members.first else { return nil }
            return "\(pr.repo.lowercased())#\(bottom)"
        }
        for task in tasks {
            guard let key = stackKey(task), let lane = organization.lane(for: task.id) else { continue }
            if stackLane[key] != .fast { stackLane[key] = lane }
        }
        for index in tasks.indices {
            let id = tasks[index].id
            tasks[index].tags = organization.tags(for: id)
            tasks[index].lane = organization.lane(for: id)
                ?? stackKey(tasks[index]).flatMap { stackLane[$0] }
                ?? .normal
        }
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
