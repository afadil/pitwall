import AgentBoardCore
import Foundation

// Read-only check against the real data on this Mac. Prints what Agent Board
// sees so it can be compared with the Claude and Codex apps and with GitHub.
// Output goes to stdout only; nothing is written anywhere.
//
//   swift run agentboard-check [--json] [--no-github]

let arguments = Set(CommandLine.arguments.dropFirst())
let wantsJSON = arguments.contains("--json")
let skipGitHub = arguments.contains("--no-github")

let paths = DataPaths.standard()
let engine = RefreshEngine(paths: paths, git: GitCLI(), gh: GHCLI())
let now = Date()
let local = await engine.readLocal(now: now)
let settings = BoardSettings()
let slugs = local.githubSlugs(settings: settings)
let github = skipGitHub ? GitHubSnapshot(fetchedAt: nil) : await engine.fetchGitHub(slugs: slugs, now: now)
let board = BoardBuilder.build(sessions: local.sessions, repos: local.repos, pullRequests: github.pullRequests, settings: settings, now: now)

let iso = ISO8601DateFormatter()

if wantsJSON {
    func sessionJSON(_ s: AgentSession) -> [String: Any] {
        [
            "app": s.app.rawValue, "id": s.sessionID, "resumeID": s.resumeID, "title": s.title,
            "branch": s.branch ?? NSNull(), "cwd": s.cwd ?? NSNull(), "archived": s.isArchived,
            "turn": s.turn.rawValue, "lastActivity": s.lastActivity.map(iso.string(from:)) ?? NSNull(),
            "repo": local.repos[s.id]?.id.key ?? NSNull(), "problem": s.problem ?? NSNull(),
        ]
    }
    func taskJSON(_ t: BoardTask) -> [String: Any] {
        var pr: Any = NSNull()
        if let p = t.pullRequest {
            pr = ["repo": p.repo, "number": p.number, "state": p.state.rawValue, "isDraft": p.isDraft,
                  "review": p.reviewDecision.rawValue, "ci": p.checks.state.rawValue, "headRefName": p.headRefName]
        }
        return ["id": t.id, "title": t.title, "column": t.column.rawValue, "reason": t.reviewReason?.rawValue ?? NSNull(),
                "sessions": t.sessions.map(\.id), "pr": pr]
    }
    let object: [String: Any] = [
        "generatedAt": iso.string(from: now),
        "sessions": local.sessions.map(sessionJSON),
        "tasks": board.tasks.map(taskJSON),
        "statuses": (local.statuses + [github.status(repoCount: slugs.count)]).map { ["kind": $0.kind.rawValue, "health": "\($0.health)", "detail": $0.detail] },
        "githubErrors": github.errors.mapValues(\.description),
    ]
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    FileHandle.standardOutput.write(data)
    print()
    exit(0)
}

func relative(_ date: Date?) -> String {
    guard let date else { return "—" }
    let minutes = Int(now.timeIntervalSince(date) / 60)
    if minutes < 60 { return "\(minutes)m" }
    if minutes < 48 * 60 { return "\(minutes / 60)h" }
    return "\(minutes / 1440)d"
}

print("Agent Board real-data check · \(iso.string(from: now))")
print("\nSources")
for status in local.statuses + [github.status(repoCount: slugs.count)] {
    print("  \(status.health)".padding(toLength: 12, withPad: " ", startingAt: 0) + "\(status.title): \(status.detail)")
}

for app in AgentApp.allCases {
    let all = local.sessions.filter { $0.app == app }
    let active = all.filter { !$0.isArchived }
    print("\n\(app.displayName): \(active.count) active, \(all.count - active.count) archived")
    for s in active {
        let repo = local.repos[s.id]?.id.displayName ?? "no repo"
        print("  \(s.turn.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(relative(s.lastActivity).padding(toLength: 5, withPad: " ", startingAt: 0)) \(s.title.prefix(60)) · \(repo) · \(s.branch ?? "no branch")\(s.problem.map { " ⚠︎ \($0)" } ?? "")")
    }
}

print("\nGitHub: \(slugs.count) repositories polled")
for slug in slugs {
    if let error = github.errors[slug] {
        print("  \(slug): can't read (\(error))")
    } else {
        print("  \(slug): \(github.pullRequests[slug]?.count ?? 0) pull requests")
    }
}

print("\nBoard: \(board.tasks.count) tasks")
for column in BoardColumn.allCases {
    let tasks = board.tasks(in: column)
    print("  \(column.title) (\(tasks.count))")
    for t in tasks {
        var line = "    \(t.title.prefix(56)) · \(t.locationLine)"
        if let pr = t.pullRequest {
            line += " · #\(pr.number) \(pr.state.rawValue) ci:\(pr.checks.state.rawValue) review:\(pr.reviewDecision.rawValue)"
        }
        if let reason = t.reviewReason { line += " [\(reason.label)]" }
        if let stack = t.stack {
            line += " stack \(stack.members.map { "#\($0)" }.joined(separator: "←"))"
            if let via = stack.workingVia { line += " (working via #\(via))" }
            if let base = stack.base { line += " (on #\(base))" }
        }
        if t.apps.count > 1 { line += " {Claude+Codex}" }
        print(line)
    }
}
