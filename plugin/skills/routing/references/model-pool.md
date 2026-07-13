# Model pool

Scores 1-10, higher better.
Sources: `user ruling 2026-07-12 · DeepSWE v1.1 leaderboard 2026-07-09 (113 tasks) · practitioner table (video, lacks 5.6)`.

## Pool

| model | runner | intel | taste | code | control | notes |
|---|---|---|---|---|---|---|
| claude-fable-5 | Agent tool | 9 | 9 | 9 | native 10 | director; judgment floor |
| claude-opus-4-8 | Agent tool | 8 | 8 | 8 | native 10 | harness/repo-law implementer |
| claude-sonnet-5 | Agent tool | 6 | 7 | 7 | native 10 | legwork |
| codex-gpt-5.6-sol | codex CLI | 8 | 8 | 9 | external 5 | DeepSWE ≈ fable at code; full access, no mid-run steering; quota-gated |

## Benchmark note

DeepSWE v1.1 — 5.6-sol peaks ~73% vs fable-5 ~70%, opus-4-8 ~52-60%,
sonnet-5 ~48-54%. Re-calibrate when a shared repo task suite exists.

## Excluded rows

- **gpt-5.5** — same price class, weaker, worst credit burn. Re-entry =
  measured ≥30% cheaper end-to-end at same pass+repair rate.
- **haiku** — user-banned.

## Friction/control

- **Agent tool** — permissions, in-band result, SendMessage resume, visible
  in token budgets.
- **codex CLI** — full access (`danger-full-access`); no mid-run steering;
  file report + log + sentinel-carries-exit-code; session-id resume only;
  audit post-hoc; INVISIBLE to harness token budgets (track separately).

## Availability

codex rows require the codex CLI installed + authed (conveyor:
`codex-exec.sh preflight`). Failing → claude-only pool; don't mention codex
options to the user.

## Quota framing

Both providers are flat-rate subscriptions. Quotas are pools that drain.
Throttle → fallback per SKILL.md ladder.
