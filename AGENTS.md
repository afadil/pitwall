# AGENTS.md

Pitwall is a native macOS app (SwiftUI). Read [README.md](README.md),
[docs/architecture.md](docs/architecture.md) and the original brief in
[docs/spec.md](docs/spec.md) first.

## Hard rules

- **Read-only on agent data.** Never write to, lock, move or delete anything under
  `~/.claude`, `~/Library/Application Support/Claude` or `~/.codex`. Open SQLite
  read-only. Never copy real transcripts or session files into this repo.
- **Synthetic fixtures only.** Test fixtures and screenshots must be hand-written,
  sanitized or demo data: no real prompts, code, paths, names or tokens.
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
- Keep `make lint` and `make test` clean. Core logic lives in `PitwallCore` with tests;
  views stay thin.
