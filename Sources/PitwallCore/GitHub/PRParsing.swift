import Foundation

/// Decodes `gh pr list --json …` output. Every field is optional on the wire;
/// entries without a number or head branch are dropped rather than failing the list.
public enum PRParsing {
    public static func pullRequests(from data: Data, repo: String) throws -> [PullRequest] {
        let raw: [RawPullRequest]
        do {
            raw = try JSONDecoder().decode([Lenient<RawPullRequest>].self, from: data).compactMap(\.value)
        } catch {
            throw GHError.unreadableOutput("expected a JSON array of pull requests")
        }
        return raw.compactMap { $0.pullRequest(repo: repo) }
    }

    /// Summarises `statusCheckRollup`, keeping only the newest run of each check
    /// (re-runs leave older cancelled or failed entries behind).
    public static func checks(from rollup: [RawCheck]) -> CheckSummary {
        var latest: [String: RawCheck] = [:]
        var anonymous: [RawCheck] = []
        for check in rollup {
            guard let key = check.identity else {
                anonymous.append(check)
                continue
            }
            if let existing = latest[key], (existing.sortDate ?? .distantPast) > (check.sortDate ?? .distantPast) {
                continue
            }
            latest[key] = check
        }

        var summary = CheckSummary()
        for check in Array(latest.values) + anonymous {
            switch check.outcome {
            case .passed: summary.passed += 1
            case .failed: summary.failed += 1
            case .pending: summary.pending += 1
            case .skipped: summary.skipped += 1
            }
        }
        return summary
    }

    static func date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty, !string.hasPrefix("0001-01-01") else { return nil }
        return Timestamp.parse(string)
    }
}

struct RawOwner: Decodable {
    var login: String?
}

struct RawLabel: Decodable {
    var name: String?
    var color: String?
}

struct RawPullRequest: Decodable {
    var number: Int?
    var title: String?
    var url: String?
    var headRefName: String?
    var headRefOid: String?
    var baseRefName: String?
    var state: String?
    var isDraft: Bool?
    var reviewDecision: String?
    var statusCheckRollup: [Lenient<RawCheck>]?
    var mergedAt: String?
    var closedAt: String?
    var updatedAt: String?
    var isCrossRepository: Bool?
    var headRepositoryOwner: RawOwner?
    var labels: [Lenient<RawLabel>]?

    func pullRequest(repo: String) -> PullRequest? {
        guard let number, let headRefName, !headRefName.isEmpty else { return nil }
        let prState: PRState =
            switch state?.uppercased() {
            case "MERGED": .merged
            case "CLOSED": .closed
            default: .open
            }
        let review: ReviewDecision =
            switch reviewDecision?.uppercased() {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            case "REVIEW_REQUIRED": .reviewRequired
            default: .none
            }
        return PullRequest(
            repo: repo,
            number: number,
            title: title ?? "Pull request #\(number)",
            url: url.flatMap(URL.init(string:)),
            headRefName: headRefName,
            headRefOid: headRefOid,
            baseRefName: baseRefName,
            state: prState,
            isDraft: isDraft ?? false,
            reviewDecision: review,
            checks: PRParsing.checks(from: (statusCheckRollup ?? []).compactMap(\.value)),
            mergedAt: PRParsing.date(mergedAt),
            closedAt: PRParsing.date(closedAt),
            updatedAt: PRParsing.date(updatedAt),
            isCrossRepository: isCrossRepository ?? false,
            headOwner: headRepositoryOwner?.login,
            labels: (labels ?? []).compactMap(\.value).compactMap { raw in
                raw.name.flatMap { $0.isEmpty ? nil : PRLabel(name: $0, color: raw.color) }
            }
        )
    }
}

/// One entry of `statusCheckRollup`: a `CheckRun` (status + conclusion) or a
/// commit `StatusContext` (state).
public struct RawCheck: Decodable, Sendable {
    var typename: String?
    var name: String?
    var context: String?
    var workflowName: String?
    var status: String?
    var conclusion: String?
    var state: String?
    var startedAt: String?
    var completedAt: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, context, workflowName, status, conclusion, state, startedAt, completedAt
    }

    enum Outcome { case passed, failed, pending, skipped }

    var identity: String? {
        if let name { return "run:\(workflowName ?? ""):\(name)" }
        if let context { return "status:\(context)" }
        return nil
    }

    var sortDate: Date? {
        PRParsing.date(completedAt) ?? PRParsing.date(startedAt)
    }

    var outcome: Outcome {
        if let state, typename == "StatusContext" || status == nil {
            switch state.uppercased() {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .pending  // PENDING, EXPECTED
            }
        }
        guard status?.uppercased() == "COMPLETED" else { return .pending }
        switch conclusion?.uppercased() {
        case "SUCCESS": return .passed
        case "NEUTRAL", "SKIPPED", "STALE": return .skipped
        case nil, "": return .pending
        default: return .failed  // FAILURE, TIMED_OUT, CANCELLED, ACTION_REQUIRED, STARTUP_FAILURE
        }
    }
}
