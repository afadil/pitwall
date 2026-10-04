# Pitwall: product spec

A small native macOS app that shows the work I do in the **Claude desktop app**
and the **Codex desktop app** as a kanban board, with each task's GitHub pull
request, CI and review state. Both a main window and a menu bar panel.

## Goals

- See every active task at a glance: what an agent is working on, what is waiting
  on me, what is in review, and what is ready to merge.
- Link each task to its pull request automatically, by git branch.
- Act from the board: open the PR, open the folder, copy the resume command, and
  (with confirmation) mark a PR ready or merge it.
- Read-only on both apps' data. No credentials besides the existing `gh` login.

## Non-goals

- Full-text search of transcripts, usage or quota tracking, other agents.
- Starting or steering agent sessions.
- Any network access other than `gh` talking to GitHub. No telemetry.

## Data sources (verified on this Mac, 2026-10-04)

All formats are internal to each app and undocumented. Parse tolerantly, ignore
unknown fields, and show a clear "can't read …" state instead of crashing when a
format changes.

### Claude desktop app

1. **Session metadata**: `~/Library/Application Support/Claude/claude-code-sessions/<a>/<b>/local_*.json`
   (two directory levels deep). One JSON object per session.
   Useful keys (types verified):
   - `sessionId` (str, `local_…`), `cliSessionId` (str)
   - `title` (str), `titleSource` (`"auto"`, `"user"` or null)
   - `isArchived` (bool)
   - `createdAt`, `lastActivityAt` (int; confirm the unit, likely epoch ms)
   - `cwd`, `originCwd` (str)
   - `gitAnchors`: null or `[{gitRoot, commonDir, trustedAt}]`. This gives the repo root, **not the branch**.
   - `completedTurns` (int), `model` (str)
2. **Transcript**: `~/.claude/projects/<encoded cwd>/<cliSessionId>.jsonl`.
   In testing, every `cliSessionId` resolved to an existing transcript.
   Each line is a JSON object with `type`, `timestamp`, `cwd`, `gitBranch`,
   `entrypoint` (`"claude-desktop"`), and for assistant turns `stopReason`.
   - Get the **branch** from the most recent line that has `gitBranch`.
   - Read only the **tail** of the file (files can be large); never load whole transcripts into memory for the board.
   - Use the tail to infer state: agent turn still in progress vs. ended and waiting on me. Validate the rule against real files before relying on it.

### Codex desktop app

1. **Thread index**: `~/.codex/state_5.sqlite` (SQLite in WAL mode), table `threads`.
   Columns include: `id`, `rollout_path`, `title`, `name`, `cwd`, `git_branch`,
   `git_origin_url`, `git_sha`, `archived`, `archived_at`, `is_pinned`,
   `created_at_ms`, `updated_at_ms`, `recency_at_ms`, `originator`, `source`,
   `first_user_message`, `preview`.
   - Open strictly read-only (`SQLITE_OPEN_READONLY`). Never write, never hold long transactions.
   - The file name is versioned. Pick the highest `state_*.sqlite` and verify the `threads` columns you need exist.
2. **Rollout files**: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (path is also in
   `threads.rollout_path`). The first line is `session_meta`, whose payload has
   `originator: "Codex Desktop"`, `cwd` and `git {branch, commit_hash, repository_url}`.
   `event_msg` records with payload type `task_started` / `task_complete`
   show whether a turn is running. Read the tail only.

### GitHub

- Use the `gh` CLI with the user's existing login. Never read or store tokens.
- Work out each task's repo from its git remote (`git -C <dir> remote get-url origin`) or Codex's `git_origin_url`, normalized to `owner/name`.
- One call per repo per refresh (about every 60 s, and on demand), for example:
  `gh pr list --repo owner/name --state all --limit 100 --json number,title,url,headRefName,state,isDraft,reviewDecision,statusCheckRollup,mergedAt,updatedAt`
- Match PRs to tasks by `headRefName` == branch. Handle forks and branches with no PR.
- If `gh` is missing or signed out, show that clearly and keep the board working without PR data.

## Model and board rules

- **Task** = one (repo, branch). Claude and Codex sessions on the same branch merge into one task card.
- Sessions on the repo's default branch, or with no branch, are shown as their own card.
- Hide archived sessions (toggle to show).

| Column         | Rule                                                                                  |
| -------------- | ------------------------------------------------------------------------------------- |
| Working        | An agent turn is in progress, or activity in the last few minutes                     |
| Waiting on you | Agent turn ended, no PR yet                                                           |
| In review      | PR open: draft, CI running, CI failing, or changes requested (show which on the card) |
| Ready to merge | PR open, approved or no review required, CI green                                     |
| Done           | PR merged or closed in the last 7 days (collapsed list)                               |

Card content: title, `repo · branch` in monospace, app badges (Claude, Codex),
relative last activity, PR number, CI state, review state.

## Actions

- Open PR in the browser; open the folder in Finder, Terminal or the default editor.
- Copy the resume command: `claude --resume <cliSessionId>` or `codex resume <thread id>` (check the exact Codex syntax with `codex --help`).
- Hide or unhide a card (local app state only).
- **Mark ready for review** and **merge** through `gh`, each behind a confirmation sheet that names the PR. These are write actions on GitHub.

## Design direction

Follow Apple's Human Interface Guidelines (https://developer.apple.com/design/)
and the references in `design/references/`:

- `menubar-panel-systemos.png`: compact dark panel. Segmented control, large
  numerals, a timeline strip of colored blocks, a "needs review" callout with
  inline actions, and dense rows with icons and right-aligned durations. Model the
  **menu bar panel** on this.
- `tactile-controls-sequencer.png`: warm orange accent on deep charcoal, soft
  rounded tactile controls, small monospace labels.
- `window-overview-prs.webp`: translucent sidebar window, icon rail, big "Overview"
  title, stat cards, a list of today's PRs. Model the **main window** chrome and an
  Overview screen on this.

Principles: dark-first that still works in light mode; system materials (vibrancy)
over flat fills; one warm accent with semantic colors kept for CI and review
state; SF Pro for UI and SF Mono for branches and small labels; continuous
rounded corners and hairline separators; sentence case; restrained, purposeful
motion. Respect Reduce Motion, Reduce Transparency, Dynamic Type where available,
VoiceOver labels and full keyboard navigation.

Screens:

1. **Board**: the kanban (main screen).
2. **Overview**: stat cards (working, waiting, in review, ready) and today's activity timeline per app.
3. **Menu bar panel**: count of tasks waiting on me, the "needs you" list with actions, and a mini timeline.
4. **Settings**: refresh interval, show archived, repos to include or exclude, and the paths of the data sources with a read status for each.

## Acceptance

- Builds and launches from the command line with no manual Xcode steps.
- Readers, rules and the GitHub matching are covered by unit tests using synthetic fixtures.
- Against the real data on this Mac, the session counts and titles match what the Claude and Codex apps show, and PR states match GitHub.
- Screenshots of every screen in dark and light mode are reviewed before calling it done.
