# Codex direct lane (yolo) — spec

User ruling 2026-07-13, superseding the same-day auto_review design (which
superseded the broker design). Full history in git + docs/DECISIONS.md.

## What

codex-gpt-5.6-sol runs UNSANDBOXED (`danger-full-access`; exec mode never
prompts) — the same trust the claude lane already gets. It edits, runs any
tests, commits, pushes feature branches, and posts its own PR reviews and
labels directly. Structure, not a sandbox, bounds the blast radius.

## Why

- Threat model: solo developer; every PR is agent-authored; no third-party
  diffs. The auto_review policy machinery defended against hostile input that
  does not exist here.
- Empirical: on issue #63 every blocker and QA failure came from the guard
  machinery itself (strict-config, canary prompt), never from the feature.
- Symmetry: Opus executors already run with full shell and the user's gh auth.
- Cost: policies/canaries/carve-outs bloated skills and burned fix rounds;
  simplicity-first is repo law.

## Decisions (locked)

- **Mechanism:** `codex-exec.sh run --sandbox danger-full-access` (exec mode,
  no approval prompts). Runner architecture unchanged: sentinel = codex exit
  code, session-id resume, visibility panes.
- **Structural guards (replace the sandbox):**
  - codex always works in a dedicated per-issue worktree;
  - GitHub branch protection on `main` (one-time setup; doctor warns when
    absent) — no direct or force pushes to main, agent or human;
  - merge, card moves, `ready-to-merge` stay orchestrator/human;
  - review gate + QA unchanged — they are the quality machinery;
  - after any push, the orchestrator waits for CI checks before the card
    advances.
- **Developer responsibility (recorded, not enforced):** machines running the
  yolo lane keep production credentials out of reachable env/keychain scope.
- **Visibility:** `--output-schema` structures reports (verdict, findings,
  commit shas, tests); `audit <log>` lists privileged commands post-hoc —
  more useful with no gate, kept.
- **Reviewer ladder and rotation unchanged** (5.6 → Fable → Opus, skip
  material authors; high-risk executor = Opus; high-risk gate = Fable +
  cross-provider opinion; volume trade-off as ratified).
- **Orchestrator pre-push judgment** applies only where the orchestrator
  pushes (claude lane): proportional — rerun load-bearing tests, stat/scope
  skim; deep read on suspicion. Codex pushes its own feature branches; the
  review gate is the deep read.
- **Dropped entirely:** auto_review config, policy templates, render-policy,
  escalation canary, PAT/HOME isolation plumbing. The gotchas records of the
  auto_review experiments stay (true, hard-won facts).

## Design

- `plugin/scripts/codex-exec.sh` — sandbox allowlist gains
  `danger-full-access`; keep `--output-schema` passthrough + `audit`; delete
  render-policy, preflight --escalations, PAT env plumbing.
- Delete `plugin/config/codex-policies/` except `report.schema.json` (used by
  `--output-schema`; move to `plugin/config/`).
- `plugin/skills/executing-tasks/SKILL.md` (S2) — codex lane: full-access in
  worktree, commits AND pushes its branch, posts its own review when gating;
  orchestrator: CI-watch after push, merge-side actions, claude-lane pre-push
  skim.
- `plugin/skills/routing/SKILL.md` + references (S2) — drop
  isolated-impl/read-only constraint; codex friction note → "full access;
  no mid-run steering; audit post-hoc".
- `plugin/skills/doctor/SKILL.md` (S2) — warn when `main` lacks branch
  protection.
- `plugin/agents/pr-reviewer.md` (S2) — transport note only: codex gate posts
  directly.
- Tests: keep output-schema + audit coverage; delete role/canary/PAT cases
  (also fixes the CI teardown race those tests carried).

## Out of scope

- auto_review / broker machinery (superseded; recorded in DECISIONS).
- Sandboxed lanes for untrusted-contributor repos — new spec if that day comes.
- MCP wiring for codex; QA-lane experiment (#62).

## Trace

- Ruling: user, 2026-07-13, after running the auto_review lane end-to-end on
  issue #63. Council designs (broker r2, auto_review r3) preserved in git
  history; their live-verified codex facts remain in docs/gotchas/codex.md.
