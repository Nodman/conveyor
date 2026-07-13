# Decisions

Each entry: `## YYYY-MM-DD — <topic>` followed by bullets — chose X over Y, because…

## 2026-07-13 — Routing paradigm: cost-ranked pool, escalation over thrift

- Pool scores rank cost instead of a code benchmark; gpt-5.5 re-admitted;
  cheap models explore first, standing permission to escalate on a missed
  bar — user ruling. Chose this over benchmark-ranked rows because flat-rate
  quotas make output quality, not per-token price, the real cost.
- The rules themselves live in `plugin/skills/routing/` (SKILL.md = policy,
  model-pool.md = data) — this entry records the shift, not the ruling.
- Codex sees skills via symlinks in `.agents/skills/` (codex scans cwd →
  repo root; worktrees are their own root, so links are made per root).
  `link-agent-skills.sh` creates them; doctor checks them; TDD is mandatory
  for codex executors same as claude ones.
- Doctor is now a session gate: run before the first conveyor activity of a
  session, not only at task pickup.

## 2026-07-13 — Codex runs yolo; structure, not a sandbox, is the guard

- Codex runs unsandboxed (`danger-full-access`, exec mode) — chose this over
  the same-day auto_review design (which had superseded the broker design),
  user ruling. Because: the threat model is a solo developer with only
  agent-authored PRs (no hostile diff source); on issue #63 every blocker and
  QA failure came from the guard machinery itself, never the feature; and the
  claude lane already runs with full shell + gh auth — the asymmetry bought
  fix rounds, not safety.
- Guards that remain (cheap, deterministic): per-issue worktrees; GitHub
  branch protection on `main` (doctor warns when absent); merge/cards/
  ready-to-merge stay orchestrator+human; review gate + QA unchanged;
  orchestrator waits for CI checks after any push before the card advances.
  Developer responsibility: no production credentials reachable on yolo hosts.
- Kept from the auto_review work: `--output-schema` reports, `audit <log>`
  post-hoc visibility, session-id resume, the live-verified codex facts in
  docs/gotchas/codex.md. Dropped: policies, render-policy, canary, PAT/HOME
  isolation plumbing.
- Codex-lane pre-push judgment: codex pushes its own feature branches; the
  review gate is the deep read. Claude-lane orchestrator pre-push check is
  proportional (tests + stat/scope skim; deep read on suspicion) — one deep
  read per PR, at the gate.
- Reviewer ladder 5.6-sol → Fable → Opus, skipping the PR's material authors;
  `family` = model lineage. High-risk implementation always routes to Opus so
  the cross-provider opinion is never a self-review.
- Ratified: 5.6 authors most code, so Fable gates most PRs by volume —
  "5.6 top reviewer" holds per-eligibility. Strongest author +
  second-strongest gate over the reverse.
- Spec: docs/specs/2026-07-13-codex-native-gate.md.

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
