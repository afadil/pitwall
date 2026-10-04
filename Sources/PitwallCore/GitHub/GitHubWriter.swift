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
        case let .merge(method):
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
        case let .notApplicable(reason): reason
        case let .gh(error): error.description
        }
    }
}

/// Proof that the user confirmed a specific pending write. Only the coordinator mints these.
public struct Confirmation: Sendable {
    let writeID: UUID
    fileprivate init(writeID: UUID) { self.writeID = writeID }
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

/// Drives the request → confirmation sheet → perform flow for write actions.
///
/// `request` only prepares a `PendingWrite` for the UI to show; nothing reaches
/// `gh` until `confirm()` is called for that same pending write.
@MainActor
@Observable
public final class WriteActionCoordinator {
    public enum Outcome: Sendable, Equatable {
        case succeeded(String)
        case failed(String)
    }

    public private(set) var pending: PendingWrite?
    public private(set) var isPerforming = false
    public private(set) var lastOutcome: Outcome?

    private let writer: GitHubWriter
    private let client: GitHubClient
    private let onSuccess: @MainActor () -> Void

    public init(runner: GHRunning, onSuccess: @escaping @MainActor () -> Void = {}) {
        self.writer = GitHubWriter(runner: runner)
        self.client = GitHubClient(runner: runner)
        self.onSuccess = onSuccess
    }

    /// Whether an action makes sense for this PR right now.
    public static func availability(of action: PRWriteAction, for pr: PullRequest) -> String? {
        guard pr.state == .open else { return "Pull request #\(pr.number) is \(pr.state.rawValue)." }
        switch action {
        case .markReady:
            return pr.isDraft ? nil : "Pull request #\(pr.number) is already ready for review."
        case .merge:
            return pr.isDraft ? "Pull request #\(pr.number) is a draft. Mark it ready first." : nil
        }
    }

    /// Prepares a write for confirmation. For merges, looks up allowed methods (a read).
    public func request(_ action: PRWriteAction, for pr: PullRequest) async {
        lastOutcome = nil
        if let reason = Self.availability(of: action, for: pr) {
            lastOutcome = .failed(reason)
            return
        }
        var allowed: [MergeMethod] = []
        var resolved = action
        if case let .merge(preferred) = action {
            allowed = (try? await client.mergeMethods(repo: pr.repo)) ?? MergeMethod.allCases
            resolved = .merge(allowed.contains(preferred) ? preferred : allowed.first ?? preferred)
        }
        pending = PendingWrite(action: resolved, pullRequest: pr, allowedMethods: allowed)
    }

    /// Changes the merge method on the pending write before confirming.
    public func choose(_ method: MergeMethod) {
        guard let current = pending, case .merge = current.action else { return }
        pending?.action = .merge(method)
    }

    public func cancel() {
        pending = nil
    }

    /// Runs the pending write. This is the only path that reaches `gh` for writes.
    public func confirm() async {
        guard let write = pending, !isPerforming else { return }
        isPerforming = true
        defer { isPerforming = false }
        do {
            try await writer.perform(write, confirmation: Confirmation(writeID: write.id))
            pending = nil
            let what = switch write.action {
            case .markReady: "marked ready for review"
            case .merge: "merged"
            }
            lastOutcome = .succeeded("Pull request #\(write.pullRequest.number) \(what).")
            onSuccess()
        } catch {
            pending = nil
            lastOutcome = .failed(error.description)
        }
    }

    public func clearOutcome() {
        lastOutcome = nil
    }
}
