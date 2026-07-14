# Auto flatten — drop the per-card lead

Issue: #71

## What

`/conveyor:auto` stops spawning a lead subagent per card. The main session
runs each card's lifecycle itself — the same flow as `/conveyor:work` — with
the auto-only gates kept: agreement prompt, spec/plan judges, auto-merge,
backlog triage, brake.

## Why

- Leads are subagents; subagents cannot spawn subagents. executing-tasks
  needs to spawn executors, reviewers, QA, judges — it stalls inside a lead.
- The middle model adds cost and drift with no benefit.

## Decisions (locked)

- Main session orchestrates every card directly; no lead, no dispatcher.
- Triage keeps the read-only classifier subagent (it spawns nothing).
- needs-spec path: main session writes the spec (brainstorming format, no
  human Q&A) and the plan (writing-plans), spawning spec-judge / plan-judge
  directly. Placement rules and 2-rejections → Human Only unchanged.
- executing-tasks' auto-merge gate re-keys from "your spawn prompt says so"
  to "the session declared a /conveyor:auto run". Step itself unchanged.
- Context hygiene: executing-tasks' durable ledger + normal session
  compaction. No new machinery.
- 2026-07-11 separate-skill ruling stands; only its "lead's spawn prompt"
  line is superseded (new DECISIONS.md entry).

## Design

`plugin/skills/auto/SKILL.md`:

- Step 4 "Dispatch loop" → "Card loop": pick top Ready card → read issue +
  linked docs → run conveyor:executing-tasks (including Auto-merge step)
  yourself. Unclear card → Human Only + `**Unblock:**`, counts as no-merge.
  Keep pick rules, brake (3 consecutive no-merge), tally, final summary.
  Drop lead spawn prompt, report contract, "never orchestrate a card
  yourself".
- Step 5 triage: classifier subagent kept; spec-lead replaced by
  main-session spec/plan writing + judge spawns per Decisions.
- Skill description line: "fresh lead per card" wording goes.

`plugin/skills/executing-tasks/SKILL.md`: gate wording tweak only (line
~115).

`docs/DECISIONS.md`: append 2026-07-13 ruling — auto flattened, reason
(nesting + middle model), gate re-keyed to in-session agreement.

`README.md`: Autonomous mode bullet "A fresh lead subagent per card…" →
main session runs the lifecycle itself.

`plugin/.claude-plugin/plugin.json`: patch bump.

Tests: update bats skill-contract assertions — auto skill has no lead
language, executing-tasks carries the new gate wording, auto still owns
auto-merge and work stays merge-free.

## Out of scope

- Any change to the Auto-merge step's preconditions or mechanics.
- Agreement prompt, permissions grant, doctor-first, sources rule.
- README beyond the one autonomous-mode bullet.
