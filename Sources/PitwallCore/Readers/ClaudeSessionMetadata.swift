import Foundation

/// Fields we use from `claude-code-sessions/<a>/<b>/local_*.json`.
public struct ClaudeSessionMetadata: Sendable, Hashable {
    public var sessionID: String
    public var cliSessionID: String?
    public var title: String?
    public var isArchived: Bool
    public var createdAt: Date?
    public var lastActivityAt: Date?
    public var cwd: String?
    public var originCwd: String?
    public var gitRoots: [String]
    /// Present on worktree sessions in newer app versions.
    public var branch: String?
    /// Pull requests the app linked to this session (`prs`), minus dismissed ones.
    public var pullRequests: [LinkedPullRequest]

    /// Parses one session file. Unknown keys are ignored; wrong types become nil.
    public static func parse(_ data: Data, fallbackID: String) -> ClaudeSessionMetadata? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let anchors = (object["gitAnchors"] as? [[String: Any]]) ?? []
        return ClaudeSessionMetadata(
            sessionID: object.string("sessionId") ?? fallbackID,
            cliSessionID: object.string("cliSessionId"),
            title: object.string("title"),
            isArchived: object.bool("isArchived") ?? false,
            createdAt: object.date("createdAt"),
            lastActivityAt: object.date("lastActivityAt"),
            cwd: object.string("cwd"),
            originCwd: object.string("originCwd"),
            gitRoots: anchors.compactMap { $0.string("gitRoot") },
            branch: object.string("branch"),
            pullRequests: ((object["prs"] as? [[String: Any]]) ?? []).compactMap(linkedPullRequest)
        )
    }

    /// `{prNumber, repo: "owner/name", host, branch, dismissed?}` → link, GitHub only.
    static func linkedPullRequest(_ entry: [String: Any]) -> LinkedPullRequest? {
        guard entry.bool("dismissed") != true,
              let slug = entry.string("repo"), let branch = entry.string("branch") else { return nil }
        let host = entry.string("host") ?? "github.com"
        guard host.lowercased() == "github.com" else { return nil }
        let parts = slug.split(separator: "/").map(String.init)
        guard parts.count == 2 else { return nil }
        let number = (entry["prNumber"] as? NSNumber)?.intValue
        return LinkedPullRequest(repo: RepoID(host: host, owner: parts[0], name: parts[1]), branch: branch, number: number)
    }
}
