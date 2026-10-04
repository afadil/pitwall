import Foundation

/// Runs read-only git commands. Behind a protocol so tests can answer for git.
public protocol GitRunning: Sendable {
    /// Runs `git -C directory <arguments>`; nil when git can't run there.
    func run(_ arguments: [String], in directory: String) async -> ProcessResult?
}

public struct GitCLI: GitRunning {
    public var executable: URL

    public init(executable: URL = URL(filePath: "/usr/bin/git")) {
        self.executable = executable
    }

    public func run(_ arguments: [String], in directory: String) async -> ProcessResult? {
        try? await ProcessRunner.run(
            executable: executable,
            arguments: ["-C", directory] + arguments,
            environment: [
                // Never take index locks or prompt for anything.
                "GIT_OPTIONAL_LOCKS": "0",
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_ASKPASS": "/usr/bin/false",
            ],
            timeout: .seconds(5)
        )
    }
}

/// Maps a session's folder to its repository, using only read-only git commands:
/// `config --get-regexp` for remotes, `symbolic-ref` for the default branch and
/// `rev-parse --git-common-dir` for checkouts without a remote.
public actor RepoResolver {
    private let git: GitRunning
    private var cache: [String: (Date, ResolvedRepo?)] = [:]
    private let lifetime: TimeInterval
    private let directoryExists: @Sendable (String) -> Bool

    public init(
        git: GitRunning,
        cacheLifetime: TimeInterval = 600,
        directoryExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) {
        self.git = git
        self.lifetime = cacheLifetime
        self.directoryExists = directoryExists
    }

    public func resolve(_ session: AgentSession, now: Date = Date()) async -> ResolvedRepo? {
        // Without a branch or a recorded remote the folder isn't a git checkout as far
        // as the apps know, so don't run git there (it may be a privacy-protected
        // folder such as ~/Documents, where git would wait for permission).
        guard session.branch != nil || session.originURL != nil else { return nil }
        let directories = ([session.cwd] + session.fallbackDirectories.map(Optional.some))
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        if let origin = session.originURL.flatMap(RepoID.fromRemote) {
            // The app recorded the remote; git only adds upstream and default branch.
            for directory in directories where directoryExists(directory) {
                if let local = await resolve(directory: directory, now: now), local.id == origin {
                    return local
                }
            }
            return ResolvedRepo(id: origin, defaultBranch: knownDefaultBranch(for: origin))
        }

        for directory in directories where directoryExists(directory) {
            if let resolved = await resolve(directory: directory, now: now) {
                return resolved
            }
        }
        return nil
    }

    public func resolve(directory: String, now: Date = Date()) async -> ResolvedRepo? {
        if let cached = cache[directory], now.timeIntervalSince(cached.0) < lifetime {
            return cached.1
        }
        let resolved = await lookUp(directory: directory)
        cache[directory] = (now, resolved)
        return resolved
    }

    private func lookUp(directory: String) async -> ResolvedRepo? {
        let remotes = await git.run(["config", "--get-regexp", #"^remote\..*\.url$"#], in: directory)
        let urls = Self.parseRemotes(remotes?.exitCode == 0 ? remotes?.stdoutString ?? "" : "")

        if let origin = urls["origin"].flatMap(RepoID.fromRemote) ?? urls.values.sorted().lazy.compactMap(RepoID.fromRemote).first {
            let head = await git.run(["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: directory)
            let defaultBranch = head?.exitCode == 0 ? Self.parseDefaultBranch(head?.stdoutString ?? "") : nil
            let upstream = urls["upstream"].flatMap(RepoID.fromRemote).flatMap { $0 == origin ? nil : $0 }
            return ResolvedRepo(id: origin, upstream: upstream, defaultBranch: defaultBranch)
        }

        // No usable remote: identify the repo by its main checkout folder so that
        // worktrees of the same repo group together.
        let commonDir = await git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: directory)
        guard commonDir?.exitCode == 0,
              let path = commonDir?.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        let root = path.hasSuffix("/.git") ? String(path.dropLast(5)) : path
        // Without a remote there's no recorded default branch; main/master is assumed.
        return ResolvedRepo(id: .local(path: root))
    }

    private func knownDefaultBranch(for repo: RepoID) -> String? {
        cache.values.lazy.compactMap(\.1).first { $0.id == repo }?.defaultBranch
    }

    /// `remote.<name>.url <url>` lines → name → url.
    static func parseRemotes(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].hasPrefix("remote."), parts[0].hasSuffix(".url") else { continue }
            let name = String(parts[0].dropFirst("remote.".count).dropLast(".url".count))
            result[name] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// `origin/main` → `main`.
    static func parseDefaultBranch(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let slash = trimmed.firstIndex(of: "/") {
            let branch = String(trimmed[trimmed.index(after: slash)...])
            return branch.isEmpty ? nil : branch
        }
        return trimmed
    }
}
