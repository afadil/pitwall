import Foundation

/// Synthetic data for previews, screenshots and `--demo` mode. Nothing here comes
/// from a real machine; the board is built with the real rules.
public enum DemoData {
    public struct Snapshot: Sendable {
        public var local: LocalSnapshot
        public var github: GitHubSnapshot
    }

    static let orbit = ResolvedRepo(id: RepoID(host: "github.com", owner: "acme", name: "orbit"), defaultBranch: "main")
    static let lumen = ResolvedRepo(id: RepoID(host: "github.com", owner: "acme", name: "lumen"), defaultBranch: "main")
    static let atlas = ResolvedRepo(id: RepoID(host: "github.com", owner: "acme", name: "atlas-api"), defaultBranch: "main")
    static let dotfiles = ResolvedRepo(id: .local(path: "/Users/demo/dotfiles"))

    public static func snapshot(now: Date = Date(), calendar: Calendar = .current) -> Snapshot {
        let day = calendar.startOfDay(for: now)
        let minutes = { (m: Double) in now.addingTimeInterval(-m * 60) }
        // Today's activity, as hours after midnight (clamped to the past).
        func spans(_ pairs: [(Double, Double)]) -> [DateInterval] {
            pairs.compactMap { start, end in
                let s = day.addingTimeInterval(start * 3600)
                let e = min(day.addingTimeInterval(end * 3600), now)
                return s < e ? DateInterval(start: s, end: e) : nil
            }
        }

        var sessions: [AgentSession] = []
        var repos: [String: ResolvedRepo] = [:]

        func add(_ app: AgentApp, _ id: String, _ title: String, _ repo: ResolvedRepo?, _ branch: String?,
                 ago: Double, turn: TurnState = .ended, activity: [(Double, Double)] = [], archived: Bool = false) {
            let folder = repo?.id.localPath ?? "/Users/demo/work/\(repo?.id.name ?? "scratch")"
            let session = AgentSession(
                app: app, sessionID: id, resumeID: "\(id)-0000-4000-8000-demo", title: title,
                cwd: folder, branch: branch, createdAt: minutes(ago + 90), lastActivity: minutes(ago),
                isArchived: archived, turn: turn, lastWrite: turn == .running ? minutes(ago) : nil,
                activity: spans(activity)
            )
            sessions.append(session)
            if let repo { repos[session.id] = repo }
        }

        // Working
        add(.claude, "c01", "Queue offline edits and sync on reconnect", orbit, "feat/offline-sync", ago: 1, turn: .running,
            activity: [(8.6, 9.4), (10.1, 11.3), (13.2, 14.0), (14.6, 24)])
        add(.codex, "x01", "Write tests for the offline queue", orbit, "feat/offline-sync", ago: 6,
            activity: [(11.0, 11.6), (14.2, 14.9)])
        add(.codex, "x02", "Return rate-limit headers on 429", atlas, "fix/rate-limit-headers", ago: 2, turn: .running,
            activity: [(9.5, 10.2), (15.0, 24)])

        // Waiting on you
        add(.claude, "c02", "Draft release notes for 4.2", lumen, "claude/brave-otter", ago: 12, activity: [(12.0, 12.8)])
        add(.codex, "x03", "Why does the upload test flake?", orbit, "main", ago: 41, activity: [(7.9, 8.4), (12.9, 13.3)])
        add(.claude, "c03", "Tidy zsh startup time", dotfiles, "main", ago: 190)
        add(.claude, "c04", "Explore SQLite FTS for search", orbit, "spike/fts", ago: 60 * 50)
        add(.codex, "x04", "Benchmark the image decoder", lumen, "codex/decoder-bench", ago: 60 * 75)

        // In review
        add(.claude, "c05", "Dark mode for settings screens", orbit, "feat/dark-mode", ago: 95, activity: [(9.0, 9.7)])
        add(.codex, "x05", "Round CSV export totals", lumen, "codex/csv-rounding", ago: 130, activity: [(10.4, 10.9)])
        add(.claude, "c06", "Retry failed webhook deliveries", atlas, "feat/webhook-retry", ago: 220)
        add(.codex, "x06", "Retry policy tests", atlas, "feat/webhook-retry", ago: 260)
        add(.codex, "x09", "Sign webhook payloads", atlas, "feat/webhook-signing", ago: 240)
        add(.claude, "c07", "Search suggestions", orbit, "feat/search", ago: 300)

        // Ready to merge
        add(.claude, "c08", "Design tokens for spacing", lumen, "feat/theme-tokens", ago: 75, activity: [(11.6, 12.0)])
        add(.codex, "x07", "October dependency bumps", atlas, "chore/deps-oct", ago: 400)

        // Done
        add(.claude, "c09", "Fix flaky upload retries", orbit, "fix/flaky-upload", ago: 60 * 26)
        add(.codex, "x08", "Accessibility labels for charts", lumen, "codex/a11y-labels", ago: 60 * 70)
        add(.claude, "c10", "Remove legacy v1 endpoint", atlas, "feat/drop-v1", ago: 60 * 120)

        func pr(_ repo: ResolvedRepo, _ number: Int, _ title: String, _ branch: String, base: String = "main", state: PRState = .open,
                draft: Bool = false, review: ReviewDecision = .none, checks: CheckSummary = CheckSummary(passed: 6, skipped: 1),
                ago: Double) -> PullRequest {
            let when = minutes(ago)
            let slug = repo.id.githubSlug ?? ""
            return PullRequest(
                repo: slug, number: number, title: title, url: URL(string: "https://github.com/\(slug)/pull/\(number)"),
                headRefName: branch, headRefOid: String(repeating: "d", count: 40), baseRefName: base,
                state: state, isDraft: draft, reviewDecision: review, checks: checks,
                mergedAt: state == .merged ? when : nil, closedAt: state == .open ? nil : when, updatedAt: when,
                isCrossRepository: false, headOwner: repo.id.owner
            )
        }

        let prs: [String: [PullRequest]] = [
            "acme/orbit": [
                pr(orbit, 412, "feat(sync): queue offline edits", "feat/offline-sync", checks: CheckSummary(passed: 4, pending: 2), ago: 8),
                pr(orbit, 409, "feat(ui): dark mode for settings", "feat/dark-mode", draft: true, ago: 95),
                pr(orbit, 405, "feat(search): suggestions", "feat/search", checks: CheckSummary(passed: 3, pending: 3), ago: 20),
                pr(orbit, 401, "fix(upload): retry on 503", "fix/flaky-upload", state: .merged, review: .approved, ago: 60 * 25),
            ],
            "acme/lumen": [
                pr(lumen, 88, "fix(export): round CSV totals", "codex/csv-rounding", checks: CheckSummary(passed: 5, failed: 1), ago: 120),
                pr(lumen, 86, "feat(tokens): spacing scale", "feat/theme-tokens", review: .approved, ago: 70),
                pr(lumen, 83, "a11y: label chart series", "codex/a11y-labels", state: .merged, review: .approved, ago: 60 * 68),
            ],
            "acme/atlas-api": [
                pr(atlas, 231, "feat(webhooks): retry with backoff", "feat/webhook-retry", review: .changesRequested, ago: 200),
                pr(atlas, 233, "feat(webhooks): sign payloads", "feat/webhook-signing", base: "feat/webhook-retry", review: .approved, ago: 230),
                pr(atlas, 229, "chore(deps): October bumps", "chore/deps-oct", ago: 380),
                pr(atlas, 224, "Remove v1 endpoint", "feat/drop-v1", state: .closed, ago: 60 * 118),
            ],
        ]

        let statuses = [
            SourceStatus(kind: .claudeSessions, path: "~/Library/Application Support/Claude/claude-code-sessions", health: .ok, detail: "10 sessions"),
            SourceStatus(kind: .claudeTranscripts, path: "~/.claude/projects", health: .ok, detail: "10 transcripts · tails only"),
            SourceStatus(kind: .codexThreads, path: "~/.codex/state_5.sqlite", health: .ok, detail: "8 threads · state_5.sqlite"),
            SourceStatus(kind: .codexRollouts, path: "~/.codex/sessions", health: .ok, detail: "8 rollouts · tails only"),
        ]
        return Snapshot(
            local: LocalSnapshot(sessions: sessions, repos: repos, statuses: statuses, readAt: now),
            github: GitHubSnapshot(pullRequests: prs, fetchedAt: now.addingTimeInterval(-40))
        )
    }

    public static func board(now: Date = Date(), calendar: Calendar = .current, settings: BoardSettings = BoardSettings()) -> Board {
        let snap = snapshot(now: now, calendar: calendar)
        return BoardBuilder.build(sessions: snap.local.sessions, repos: snap.local.repos,
                                  pullRequests: snap.github.pullRequests, settings: settings, now: now)
    }
}
