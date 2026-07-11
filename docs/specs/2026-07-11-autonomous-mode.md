# Autonomous mode (`/conveyor:work auto`)

## What

One argument turns `/conveyor:work` into a self-driving run: drain Ready for
dev, triage Backlog, spec/plan via judge agents instead of human gates,
auto-merge PRs, stop when the board is empty. Plain `/conveyor:work` is
unchanged.

## Why

- Human merge/approval gates cap throughput when the human wants the board
  drained unattended.
- Issues filed during execution land in Backlog and today wait for a human;
  auto mode must consume them too.
- Long runs must not degrade: no orchestrator may accumulate unbounded
  context.

## Decisions (locked)

- Toggle: per-run argument `/conveyor:work auto`. No durable config flag.
- Spec/plan approval in auto mode: full self-approval via specialized judge
  agents (spec-judge, plan-judge) acting in place of the human.
- Long-run survival: dispatcher pattern — fresh lead subagent per card; no
  token-threshold self-handoff.
- Scope of a run: drain Ready for dev, then triage Backlog, repeat until both
  empty. Brake: 3 consecutive failed/blocked cards → stop and report.
- Human Only column is never touched. Cards are never moved to Done by agents
  (GitHub "Item closed → Done" automation does it on merge via `Fixes #n`).
- Merge method: `gh pr merge --squash --delete-branch`.
- Philosophy change accepted: README + plugin.json description change from
  "human merges" to "merge is human-gated unless the user launches an auto
  run".

## Design

### Toggle + consent

- `work` skill parses `auto` argument; auto rules apply to that run only.
- First auto run per repo: consent gate (AskUserQuestion). On yes →
  `scaffold.sh --grant-auto-merge`:
  - `permissions.allow` += `Bash(gh pr merge:*)`
  - `autoMode.allow` += standing rule: during a declared `/conveyor:work
    auto` run, squash-merging PRs carrying `ready-to-merge` is
    pre-authorized; moving cards to Done stays excluded.
  - Idempotent (jq set-difference, same pattern as `--grant-label-perms`).
- Consent detection: both entries already present → skip the gate. Declined →
  auto run refuses to start; offer a plain run.

### Dispatcher loop (work skill, auto section)

1. `/conveyor:doctor` once at start.
2. Pick top Ready card (existing priority rules) → spawn a fresh lead
   subagent for that one card. Lead runs the full executing-tasks lifecycle
   (executors, pr-reviewer, qa-agent — unchanged) plus the merge step.
3. Read the lead's report (contract: merged sha | blocked reason | issues
   filed, one short paragraph). Update run tally. Release the lead.
4. Ready empty → backlog triage: spawn a triage agent that classifies every
   Backlog issue:
   - `groomed` (clear acceptance criteria) → dispatcher moves it to Ready.
   - `needs-spec` (feature-sized) → dispatcher spawns a spec-lead per issue.
   - `human` (needs credentials/decisions) → Human Only + `**Unblock:**`
     comment.
   Then resume draining Ready.
5. Stop when Ready + Backlog both empty, or brake trips (3 consecutive
   failed/blocked cards). A card counts as failed/blocked when its lead ends
   without a merge — including a park to Human Only; merges reset the
   counter. Final summary: cards merged, issues filed, cards parked, brake
   state.

Dispatcher never orchestrates a card itself; it accumulates only per-card
reports.

### Judge agents (new: `plugin/agents/spec-judge.md`, `plugin/agents/plan-judge.md`)

- spec-judge: judges a spec as the human gate would — sections complete
  (What/Why/Decisions/Design/Out of scope), no placeholders, no
  contradictions, no two-way-interpretable requirements, scope matches the
  issue. Verdict: approve/reject + findings.
- plan-judge: judges plan-vs-spec — every requirement maps to a task, exact
  paths, real code in TDD steps, sane board mapping. Same verdict contract.
- Approval recorded as issue comment: `**[spec-judge]** Approved <path>`
  (audit trail). Judges never edit files.
- Spec-lead flow: write spec → spec-judge → writing-plans → plan-judge →
  slice into Ready cards. One fix round per rejection; 2 rejections on the
  same artifact → Human Only with the draft attached, dispatcher moves on.

### Merge step (per-card lead, auto runs only)

Runs after `ready-to-merge` is applied; all existing gates unchanged.

1. Preconditions: CI checks green (`gh pr checks`); no unresolved
   `**Human required:**` checklist on the PR. Either fails → card to Human
   Only + `**Unblock:**`, no merge, report back.
2. Merge conflict → rebase with explicit `git -C <path>` (worktree gotcha),
   push. Push invalidates `qa-passed` per existing rules → re-run QA → retry
   merge.
3. `gh pr merge --squash --delete-branch`. Issue closes via `Fixes #n`;
   board automation moves the card to Done.

### Files touched

- `plugin/skills/work/SKILL.md` — `auto` argument: dispatcher, triage,
  brake, stop conditions, consent gate.
- `plugin/skills/executing-tasks/SKILL.md` — auto-mode addendum: merge step,
  Human-required handling; "A human merges" becomes conditional on mode.
- `plugin/agents/spec-judge.md`, `plugin/agents/plan-judge.md` — new.
- `plugin/scripts/scaffold.sh` — `--grant-auto-merge`.
- `README.md` — auto-mode section + schema/philosophy note.
- `plugin/.claude-plugin/plugin.json` — description tweak + version bump.

### Testing

- bats: `--grant-auto-merge` writes both entries; idempotent on re-run;
  preserves existing allow entries; works on a settings.json missing
  `autoMode`.
- Skill/agent prose: live smoke per `running-the-app`.

## Out of scope

- Durable config toggle (`/conveyor:auto on|off`, mergePolicy: "auto").
- Per-run card caps.
- Parallel leads (one card at a time keeps board moves race-free).
- Any change to pr-reviewer / qa-agent charters.
