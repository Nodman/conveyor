# Plan: auto flatten — drop the per-card lead (#71)

Spec: docs/specs/2026-07-13-auto-flatten.md

**Goal:** `/conveyor:auto`'s main session runs each card's lifecycle itself
(same flow as `/conveyor:work`); the lead layer is deleted.

**Architecture:** prose-only change to two skill files plus docs. Contract is
enforced by `tests/structure.bats` grep assertions, so TDD = tighten the
assertions first, watch them fail, rewrite the skills, watch them pass.

**Global constraints:**
- Auto-merge step mechanics untouched (spec: out of scope).
- The substring `declared auto run` must survive in executing-tasks
  (existing test at tests/structure.bats:97).
- `**[team-lead]**` in executing-tasks stays — unrelated orchestrator prefix.
- Version bump: 0.1.23 → 0.1.24.

## File map

- `tests/structure.bats` — extend the auto-contract test: no lead, session
  runs executing-tasks.
- `plugin/skills/auto/SKILL.md` — description + steps 4-5 rewritten; the
  only file whose meaning changes.
- `plugin/skills/executing-tasks/SKILL.md` — auto gate re-keyed to the
  in-session declaration (one sentence).
- `README.md` — one autonomous-mode bullet.
- `docs/DECISIONS.md` — append 2026-07-13 ruling.
- `plugin/.claude-plugin/plugin.json` — version 0.1.24.

## Task 1 — auto skill rewrite, test-first

Files: `tests/structure.bats`, `plugin/skills/auto/SKILL.md`.
Interfaces: none consumed; produces the final auto SKILL.md text.

- [ ] In `tests/structure.bats`, extend the test at line 81
  ("auto skill owns the auto-mode contract; work skill stays merge-free"),
  adding after the `plan-judge` assertion:

  ```bash
  ! grep -qwi -- 'lead' "$f"
  grep -qF -- 'conveyor:executing-tasks' "$f"
  grep -qF -- 'Auto-merge step' "$f"
  ```

- [ ] `bats tests/structure.bats` → that test FAILS (auto skill still says
  "lead"); every other test passes.
- [ ] Rewrite `plugin/skills/auto/SKILL.md`. Frontmatter description becomes:

  ```
  description: Use ONLY when the human explicitly invokes /conveyor:auto — an autonomous run that drains Ready for dev + Backlog with no human gates: the session runs each card itself, judge-approved specs/plans, auto-merge. Opens with a per-run agreement prompt.
  ```

  Steps 1-3 and 6 unchanged. Steps 4-5 replaced with:

  ```markdown
  4. **Card loop.** You run every card yourself — the /conveyor:work flow
     with auto gates, nobody in between. Spawn only the workers
     conveyor:executing-tasks defines (executors, pr-reviewer, qa-agent);
     its ledger is the durable state — no extra bookkeeping.
     - Pick the top Ready-for-dev card (rules in step 3).
     - `gh issue view <n>` + every linked doc. Unclear acceptance criteria
       or human decision needed → `card.sh move <n> humanOnly` +
       `**Unblock:**` comment; counts as no-merge.
     - Run conveyor:executing-tasks on the card, including its Auto-merge
       step — this session declared a /conveyor:auto run.
     - Tally: merged → brake counter resets; anything else → +1.
     - Ready empty → Backlog triage (step 5), then resume the loop.
     - Stop on: Ready + Backlog both empty, or 3 consecutive no-merge cards
       (brake). Final summary: merged / filed / parked / brake state.
  5. **Backlog triage.** Spawn one read-only classifier agent: read every
     open Backlog issue, classify each `groomed | needs-spec | human` +
     one-line reason; report only the classification. Then act yourself:
     - groomed → `card.sh move <n> ready`
     - human → `card.sh move <n> humanOnly` + `**Unblock:**` comment
     - needs-spec → write the spec yourself (brainstorming skill format;
       decisions come from the issue + docs, no human Q&A) → spawn
       spec-judge → conveyor:writing-plans → spawn plan-judge. On approval,
       place the work: single-PR plan → move the ORIGINAL issue to Ready
       with the spec/plan linked in a comment (it becomes the work card);
       multi-PR plan → file one issue per slice, comment the slice links on
       the original, then close the original as superseded (board
       automation moves it to Done — you never move the card yourself). A
       judge rejection gets one fix round; 2 rejections on the same
       artifact → `card.sh move <n> humanOnly` with the draft linked.
  ```

- [ ] `bats tests/structure.bats` → all pass. `bats tests` → all pass.
- [ ] Commit: `feat(auto): flatten — session runs each card, no lead (#71)`

## Task 2 — gate re-key + docs + version

Files: `plugin/skills/executing-tasks/SKILL.md`, `README.md`,
`docs/DECISIONS.md`, `plugin/.claude-plugin/plugin.json`.
Interfaces: consumes Task 1's auto skill text (DECISIONS wording must match).

TDD n/a — README/DECISIONS/version have no test seam; the executing-tasks
sentence keeps the already-asserted `declared auto run` substring.
Verification step below instead.

- [ ] `plugin/skills/executing-tasks/SKILL.md` line ~115:

  ```
  old: Declared auto runs (your spawn prompt says so): run the Auto-merge step
  new: Declared auto runs (the session declared /conveyor:auto): run the Auto-merge step
  ```

- [ ] `README.md` line ~131, replace the bullet:

  ```
  old: - A fresh lead subagent per card runs the full lifecycle and squash-merges
       once CI is green and `ready-to-merge` is applied.
  new: - The session runs each card's full lifecycle itself and squash-merges
       once CI is green and `ready-to-merge` is applied.
  ```

- [ ] Append to `docs/DECISIONS.md`:

  ```markdown
  ## 2026-07-13 — Auto flattened: no per-card lead

  - Leads are subagents and subagents cannot spawn subagents — the lifecycle
    stalled inside the lead; the middle model added cost and drift.
  - The main session runs each card itself (the /conveyor:work flow); auto
    gates unchanged. Triage keeps only the read-only classifier; the session
    writes specs/plans and spawns the judges.
  - The auto-merge gate keys to the in-session /conveyor:auto declaration.
    Supersedes the "lead's spawn prompt" line of the 2026-07-11 ruling; the
    separate-skill decision stands.
  ```

- [ ] `plugin/.claude-plugin/plugin.json`: `"version": "0.1.24"`.
- [ ] Verify: `bats tests` all pass; `grep -rwin lead plugin/skills/auto/
  README.md` → no hits; `grep -c 'declared auto run'
  plugin/skills/executing-tasks/SKILL.md` → ≥1.
- [ ] Commit: `docs: re-key auto gate to session declaration; ruling + README (#71)`

## Board mapping

Single-PR plan → no new issues; #71 is the card, already In Progress.
