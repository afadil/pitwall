import Foundation

/// Owns the readers and caches. All disk and process work happens here, off the main actor.
public actor RefreshEngine {
    private let claude: ClaudeReader
    private let codex: CodexReader
    private let resolver: RepoResolver
    private let github: GitHubClient
    private var lastGood: [String: [PullRequest]] = [:]

    public init(
        paths: DataPaths,
        git: GitRunning,
        gh: GHRunning,
        directoryExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.claude = ClaudeReader(paths: paths)
        self.codex = CodexReader(codexHome: paths.codexHome)
        self.resolver = RepoResolver(git: git, directoryExists: directoryExists)
        self.github = GitHubClient(runner: gh)
    }

    public func readLocal(now: Date = Date(), calendar: Calendar = .current) async -> LocalSnapshot {
        let claudeRead = claude.read(now: now, calendar: calendar)
        let codexRead = codex.read(now: now, calendar: calendar)
        let sessions = claudeRead.items + codexRead.items

        var repos: [String: ResolvedRepo] = [:]
        for session in sessions {
            if let resolved = await resolver.resolve(session, now: now) {
                repos[session.id] = resolved
            }
        }
        return LocalSnapshot(
            sessions: sessions,
            repos: repos,
            statuses: claudeRead.statuses + codexRead.statuses,
            readAt: now
        )
    }

    /// Fetches pull requests for each repo in parallel. A repo that fails keeps
    /// its last good list so the board doesn't flicker on a transient error.
    public func fetchGitHub(slugs: [String], now: Date = Date()) async -> GitHubSnapshot {
        guard !slugs.isEmpty else { return GitHubSnapshot(fetchedAt: now) }
        let client = github
        let results = await withTaskGroup(of: (String, Result<[PullRequest], GHError>).self) { group in
            for slug in slugs {
                group.addTask {
                    do {
                        return (slug, .success(try await client.pullRequests(repo: slug)))
                    } catch let error as GHError {
                        return (slug, .failure(error))
                    } catch {
                        return (slug, .failure(.failed(exitCode: -1, message: error.localizedDescription)))
                    }
                }
            }
            var collected: [(String, Result<[PullRequest], GHError>)] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var snapshot = GitHubSnapshot(fetchedAt: now)
        for (slug, result) in results {
            switch result {
            case let .success(prs):
                lastGood[slug] = prs
                snapshot.pullRequests[slug] = prs
            case let .failure(error):
                snapshot.errors[slug] = error
                if let previous = lastGood[slug] { snapshot.pullRequests[slug] = previous }
            }
        }
        return snapshot
    }
}
