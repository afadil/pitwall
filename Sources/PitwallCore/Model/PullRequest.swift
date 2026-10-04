import Foundation

public enum PRState: String, Sendable, Codable, Hashable {
    case open
    case closed
    case merged
}

public enum ReviewDecision: String, Sendable, Codable, Hashable {
    case approved
    case changesRequested
    case reviewRequired
    /// No decision: either no review is required or nobody has reviewed yet.
    case none
}

public enum CIState: String, Sendable, Codable, Hashable {
    /// No checks reported.
    case none
    case pending
    case passing
    case failing
}

/// Counts of the latest run of each check on the PR head.
public struct CheckSummary: Sendable, Codable, Hashable {
    public var passed: Int
    public var failed: Int
    public var pending: Int
    public var skipped: Int

    public init(passed: Int = 0, failed: Int = 0, pending: Int = 0, skipped: Int = 0) {
        self.passed = passed
        self.failed = failed
        self.pending = pending
        self.skipped = skipped
    }

    public var total: Int { passed + failed + pending + skipped }

    public var state: CIState {
        if failed > 0 { return .failing }
        if pending > 0 { return .pending }
        if passed + skipped > 0 { return .passing }
        return .none
    }
}

/// A GitHub label on a pull request (read-only here).
public struct PRLabel: Sendable, Codable, Hashable {
    public var name: String
    /// Hex colour without `#`, as GitHub stores it.
    public var color: String?

    public init(name: String, color: String? = nil) {
        self.name = name
        self.color = color
    }
}

public struct PullRequest: Sendable, Codable, Hashable, Identifiable {
    /// `owner/name` of the repository the PR was opened against.
    public var repo: String
    public var number: Int
    public var title: String
    public var url: URL?
    public var headRefName: String
    public var headRefOid: String?
    public var baseRefName: String?
    public var state: PRState
    public var isDraft: Bool
    public var reviewDecision: ReviewDecision
    public var checks: CheckSummary
    public var mergedAt: Date?
    public var closedAt: Date?
    public var updatedAt: Date?
    public var isCrossRepository: Bool
    /// Login of the account that owns the head branch's repository.
    public var headOwner: String?
    public var labels: [PRLabel]

    public init(
        repo: String,
        number: Int,
        title: String,
        url: URL? = nil,
        headRefName: String,
        headRefOid: String? = nil,
        baseRefName: String? = nil,
        state: PRState,
        isDraft: Bool = false,
        reviewDecision: ReviewDecision = .none,
        checks: CheckSummary = CheckSummary(),
        mergedAt: Date? = nil,
        closedAt: Date? = nil,
        updatedAt: Date? = nil,
        isCrossRepository: Bool = false,
        headOwner: String? = nil,
        labels: [PRLabel] = []
    ) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.headRefName = headRefName
        self.headRefOid = headRefOid
        self.baseRefName = baseRefName
        self.state = state
        self.isDraft = isDraft
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.mergedAt = mergedAt
        self.closedAt = closedAt
        self.updatedAt = updatedAt
        self.isCrossRepository = isCrossRepository
        self.headOwner = headOwner
        self.labels = labels
    }

    public var id: String { "\(repo)#\(number)" }

    /// When the PR left the open state, if it has.
    public var finishedAt: Date? {
        switch state {
        case .open: nil
        case .merged: mergedAt ?? closedAt ?? updatedAt
        case .closed: closedAt ?? updatedAt
        }
    }
}

public enum MergeMethod: String, Sendable, Codable, CaseIterable, Hashable, Identifiable {
    case squash
    case merge
    case rebase

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .squash: "Squash and merge"
        case .merge: "Create a merge commit"
        case .rebase: "Rebase and merge"
        }
    }

    var flag: String { "--\(rawValue)" }
}
