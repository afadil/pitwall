import Foundation
import Observation

/// The two write actions the app can take on GitHub.
public enum PRWriteAction: Sendable, Hashable {
    case markReady
    case merge(MergeMethod)

    public var verb: String {
        switch self {
        case .markReady: "Mark ready for review"
        case .merge: "Merge"
        }
    }
}

/// A write that has been requested but not yet confirmed. Creating one has no side effects.
public struct PendingWrite: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var action: PRWriteAction
    public let pullRequest: PullRequest
    /// Merge methods the repo allows (only for merges).
    public var allowedMethods: [MergeMethod]

    init(action: PRWriteAction, pullRequest: PullRequest, allowedMethods: [MergeMethod]) {
        self.id = UUID()
        self.action = action
        self.pullRequest = pullRequest
        self.allowedMethods = allowedMethods
    }

    /// The `gh` arguments this write will run.
    public var arguments: [String] {
        let pr = pullRequest
        switch action {
        case .markReady:
            return ["pr", "ready", String(pr.number), "--repo", pr.repo]
        case .merge(let method):
            var args = ["pr", "merge", String(pr.number), "--repo", pr.repo, method.flag]
            // Refuse to merge if new commits were pushed after the user looked.
            if let sha = pr.headRefOid { args += ["--match-head-commit", sha] }
            return args
        }
    }
}

public enum WriteError: Error, Sendable, Equatable, CustomStringConvertible {
    case notConfirmed
    case notApplicable(String)
    case gh(GHError)

    public var description: String {
        switch self {
        case .notConfirmed: "The action wasn't confirmed."
        case .notApplicable(let reason): reason
        case .gh(let error): error.description
        }
    }
}

/// Runs confirmed writes. Refuses anything without a matching confirmation.
public struct GitHubWriter: Sendable {
    public let runner: GHRunning

    public init(runner: GHRunning) {
        self.runner = runner
    }

    public func perform(_ write: PendingWrite, confirmation: Confirmation?) async throws(WriteError) {
        guard let confirmation, confirmation.writeID == write.id else { throw .notConfirmed }
        let result: ProcessResult
        do {
            result = try await runner.run(write.arguments)
        } catch let error as GHError {
            throw .gh(error)
        } catch {
            throw .gh(.failed(exitCode: -1, message: error.localizedDescription))
        }
        guard result.exitCode == 0 else { throw .gh(GHError.from(result)) }
    }
}
