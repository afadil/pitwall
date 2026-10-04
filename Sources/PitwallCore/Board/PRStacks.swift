import Foundation

/// Open pull requests that target each other's branches, grouped into stacks.
///
/// `main ← feat/a (#1) ← feat/b (#2)` is one stack: #2's base branch is #1's head.
/// Only open, same-repository PRs take part; a fork's branch can't be another PR's base.
struct PRStacks {
    struct Stack {
        /// Identifies the stack: its bottom PR.
        var id: String
        /// PR numbers, bottom (targets the default branch) first.
        var members: [Int]
    }

    private var openByHead: [String: [String: PullRequest]] = [:]
    private var stackIDByPR: [String: String] = [:]
    private var stacksByID: [String: Stack] = [:]

    init(pullRequests: [String: [PullRequest]]) {
        for (slug, prs) in pullRequests {
            for pr in prs where pr.state == .open && !pr.isCrossRepository {
                openByHead[slug.lowercased(), default: [:]][pr.headRefName] = pr
            }
        }

        var members: [String: [(depth: Int, number: Int)]] = [:]
        for pr in openByHead.values.flatMap(\.values) {
            let (chain, isCycle) = chainToBottom(from: pr)
            // A cycle has no bottom; name it after its smallest member so every PR in it agrees.
            let id = isCycle ? chain.map(Self.key).min()! : Self.key(chain[chain.count - 1])
            stackIDByPR[Self.key(pr)] = id
            members[id, default: []].append((chain.count - 1, pr.number))
        }
        for (id, entries) in members {
            let ordered = entries.sorted { ($0.depth, $0.number) < ($1.depth, $1.number) }.map(\.number)
            stacksByID[id] = Stack(id: id, members: ordered)
        }
    }

    /// The open PR whose head branch this PR targets.
    func base(of pr: PullRequest) -> PullRequest? {
        guard let baseRef = pr.baseRefName, baseRef != pr.headRefName else { return nil }
        return openByHead[pr.repo.lowercased()]?[baseRef]
    }

    /// The stack an open PR belongs to (a lone PR is a stack of one).
    func stack(containing pr: PullRequest) -> Stack? {
        stackIDByPR[Self.key(pr)].flatMap { stacksByID[$0] }
    }

    /// `pr`, its base, its base's base… down to the bottom, and whether that walk
    /// ran into a cycle instead.
    private func chainToBottom(from pr: PullRequest) -> (chain: [PullRequest], isCycle: Bool) {
        var chain = [pr]
        var seen: Set<Int> = [pr.number]
        while let next = base(of: chain[chain.count - 1]) {
            guard seen.insert(next.number).inserted else { return (chain, true) }
            chain.append(next)
        }
        return (chain, false)
    }

    private static func key(_ pr: PullRequest) -> String {
        "\(pr.repo.lowercased())#\(pr.number)"
    }
}
