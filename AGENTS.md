# AGENTS.md

Native macOS app (SwiftUI) described in `SPEC.md`. Read it first.

## Hard rules

- **Read-only on agent data.** Never write to, lock, move or delete anything under
  `~/.claude`, `~/Library/Application Support/Claude` or `~/.codex`. Open SQLite
  read-only. Never copy real transcripts or session files into this repo.
- **Synthetic fixtures only.** Test fixtures must be hand-written or sanitized: no
  real prompts, code, paths, names or tokens from this machine.
- **No secrets.** Never read `~/.codex/auth.json`, the Keychain, browser cookies or
  any token. GitHub access goes only through the `gh` CLI.
- **No network** except `gh` talking to GitHub. No telemetry, analytics or update
  checks.
- **No GitHub writes during development or tests.** Mark-ready and merge must use a
  fake `gh` in tests. Never run them against real pull requests.
- **Commits:** no `Co-Authored-By: Claude` trailers and no "Generated with Claude
  Code" lines. Do not create a GitHub repo or push without asking.

## Working agreements

- Prefer the smallest readable design that meets the spec. No speculative features.
- Keep parsing tolerant. A format change should show a clear "can't read …" state, never a crash.
- Report what was tested and what was not. Don't claim a check passed if it didn't run.
