# Decisions

Each entry: `## YYYY-MM-DD — <topic>` followed by bullets — chose X over Y, because…

## 2026-07-12 — Model routing lives inside conveyor

- Routing skill ships in `plugin/skills/routing/`, not a second plugin
  (reverses the council-session two-plugin plan), because a routing-only
  install has no runner — policy without execution is useless standalone.
  Extract later if a second real consumer appears.
- Routing rules and pool are human-editable markdown (skill + references +
  optional `.claude/routing.md` override) — no JSON knobs, no setup wizard.
- No dollar/plan cost modeling: both providers are flat-rate subscriptions;
  rank models by capability (benchmarks preferred), treat quotas as pools
  with fallback on throttle.
- Council verdict + full debate archived in `.conveyor/council-routing/`.

## 2026-07-11 — Lifecycle hygiene rulings

- Label permissions: granted only via `scaffold.sh --grant-label-perms` after
  an explicit user yes — consent gate over silent settings writes.
- Human-required follow-ups: hybrid — merge-time actions → one
  `**Human required:**` PR comment; scope/credential or PR-outliving work →
  Human Only card with `**Unblock:**`. Chosen over cards-for-everything to
  keep the board signal high.
- Every agent-authored PR/issue comment carries a `**[<agent-name>]**` prefix.
- Plugin PRs bump the `plugin.json` patch version; consumers pull via
  `claude plugin marketplace update` + `claude plugin update`.

## 2026-07-11 — Autonomous mode is a separate skill

- `/conveyor:auto` over an `auto` argument on `/conveyor:work`, because
  merge-authorizing prose must be absent from plain-run context — absence is
  a harder gate than a mode conditional (drift/compaction can lose a flag).
- The only shared fork is executing-tasks' Auto-merge step, gated by the
  "declared auto run" sentence in the lead's spawn prompt.
