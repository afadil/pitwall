import Foundation

/// Identity of a repository: a hosted remote (`github.com/owner/name`) or, when a
/// checkout has no remote, its local root folder.
public struct RepoID: Hashable, Sendable, Codable, Comparable {
    public var host: String?
    public var owner: String?
    public var name: String
    public var localPath: String?

    public init(host: String?, owner: String?, name: String, localPath: String? = nil) {
        self.host = host?.lowercased()
        self.owner = owner
        self.name = name
        self.localPath = localPath
    }

    public static func local(path: String) -> RepoID {
        let trimmed = path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : path
        return RepoID(host: nil, owner: nil, name: (trimmed as NSString).lastPathComponent, localPath: trimmed)
    }

    /// Stable key used for task identity and settings.
    public var key: String {
        if let host, let owner {
            return "\(host)/\(owner)/\(name)".lowercased()
        }
        return "local:\(localPath ?? name)"
    }

    /// `owner/name` for hosted repos, folder name for local ones.
    public var displayName: String {
        if let owner { return "\(owner)/\(name)" }
        return name
    }

    /// `owner/name` when the repo lives on github.com, which is all `gh` is asked about.
    public var githubSlug: String? {
        guard host == "github.com", let owner else { return nil }
        return "\(owner)/\(name)"
    }

    public static func < (lhs: RepoID, rhs: RepoID) -> Bool {
        lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    /// Parses the remote URL forms git accepts:
    /// `https://host/owner/name(.git)`, `ssh://git@host[:port]/owner/name`,
    /// and scp-like `git@host:owner/name`.
    public static func fromRemote(_ raw: String) -> RepoID? {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }

        var host: String
        var path: String

        if let schemeRange = url.range(of: "://") {
            url = String(url[schemeRange.upperBound...])
            guard let slash = url.firstIndex(of: "/") else { return nil }
            var authority = String(url[..<slash])
            path = String(url[url.index(after: slash)...])
            if let at = authority.lastIndex(of: "@") {
                authority = String(authority[authority.index(after: at)...])
            }
            if let colon = authority.firstIndex(of: ":") {
                authority = String(authority[..<colon])
            }
            host = authority
        } else if let colon = url.firstIndex(of: ":"), !url.hasPrefix("/") {
            var authority = String(url[..<colon])
            path = String(url[url.index(after: colon)...])
            if let at = authority.lastIndex(of: "@") {
                authority = String(authority[authority.index(after: at)...])
            }
            host = authority
        } else {
            return nil
        }

        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        while path.hasPrefix("/") { path.removeFirst() }

        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2, !host.isEmpty else { return nil }
        let name = parts[parts.count - 1]
        let owner = parts[0..<(parts.count - 1)].joined(separator: "/")
        guard !name.isEmpty, !owner.isEmpty else { return nil }
        host = host.lowercased()
        if host == "www.github.com" { host = "github.com" }
        return RepoID(host: host, owner: owner, name: name)
    }
}

/// What git told us about a session's folder.
public struct ResolvedRepo: Hashable, Sendable {
    public var id: RepoID
    /// `upstream` remote, when the checkout is a fork.
    public var upstream: RepoID?
    public var defaultBranch: String?

    public init(id: RepoID, upstream: RepoID? = nil, defaultBranch: String? = nil) {
        self.id = id
        self.upstream = upstream
        self.defaultBranch = defaultBranch
    }

    /// Repos whose pull requests may belong to this checkout.
    public var pullRequestSources: [String] {
        [id.githubSlug, upstream?.githubSlug].compactMap { $0 }
    }

    public func isDefaultBranch(_ branch: String) -> Bool {
        if let defaultBranch { return branch == defaultBranch }
        return branch == "main" || branch == "master"
    }
}
