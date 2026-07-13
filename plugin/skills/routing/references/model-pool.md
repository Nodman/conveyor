# Model pool

Scores 1-10, higher better.

## Pool

| model | runner | intel | taste | cost | control | notes |
|---|---|---|---|---|---|---|
| claude-fable-5 | Agent tool | 9 | 9 | 2 | native 10 | director; judgment floor |
| claude-opus-4-8 | Agent tool | 7 | 8 | 4 | native 10 | harness/repo-law implementer |
| claude-sonnet-5 | Agent tool | 5 | 6 | 5 | native 10 | legwork, fetch docs, etc |
| codex-gpt-5.6-sol | codex CLI | 8 | 8 | 6 | external 5 | ≈ fable at code but cheaper |
| codex-gpt-5.5 | codex CLI | 7 | 5 | 7 | external 5 | ≈ opus 4.8 at code but cheaper |

## Excluded rows

- **haiku** — user-banned.

## Friction/control

- **Agent tool** — permissions, in-band result, SendMessage resume, visible
  in token budgets.
- **codex CLI** — file report + log + sentinel-carries-exit-code, session-id
  resume only, no mid-run steering, INVISIBLE to harness token budgets (track
  separately), parallel writes need worktree isolation.

## Availability

codex rows require the codex CLI installed + authed (conveyor:
`codex-exec.sh preflight`). Failing → claude-only pool; don't mention codex
options to the user.

## Quota framing

Both providers are flat-rate subscriptions. Quotas are pools that drain.
Throttle → fallback per SKILL.md ladder.
