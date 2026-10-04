import Foundation
import Observation

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

    /// Called after a write succeeds, e.g. to refresh the board.
    public var onSuccess: @MainActor () -> Void
    private let writer: GitHubWriter
    private let client: GitHubClient

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
        do throws(WriteError) {
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

/// Proof that the user confirmed a specific pending write. Only the coordinator mints these.
public struct Confirmation: Sendable {
    let writeID: UUID
    fileprivate init(writeID: UUID) { self.writeID = writeID }
}
