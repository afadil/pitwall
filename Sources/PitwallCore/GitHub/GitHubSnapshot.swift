import Foundation

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
            return SourceStatus(
                kind: .github, path: path, health: errors.count >= repoCount ? .error : .warning,
                detail: "Can't read pull requests for \(failed)\(first)")
        }
        return SourceStatus(
            kind: .github, path: path, health: .ok,
            detail: "Signed in · \(repoCount) repositor\(repoCount == 1 ? "y" : "ies")")
    }
}
