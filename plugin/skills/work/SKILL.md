---
name: work
description: Use when the human says "work on the project / pick up the next task". Picks the top Ready-for-dev card and runs the full lifecycle.
---

# /conveyor:work

1. `/conveyor:doctor` first; surface drift before starting.
2. Pick: `gh project item-list <project> --owner <owner> --limit 200 --format
   json` → open issues in "Ready for dev", highest Priority first (P1 > P2 >
   P3; unset = P2); ties → oldest. Tell the user what you picked and why.
3. `gh issue view <n>` + every linked doc. Acceptance criteria unclear or
   human decision needed → comment on the issue, move to humanOnly with an
   `**Unblock:**` comment, pick the next card.
4. New-feature-sized and no spec exists → conveyor:brainstorming →
   conveyor:writing-plans first. Groomed task with clear criteria → straight
   to conveyor:executing-tasks.
5. Definition of done = executing-tasks' merge-ready report. Repeat from
   step 2 only if the human asked for continuous pickup.

## Auto mode (`/conveyor:work auto`)

The `auto` argument makes this run autonomous: no human gates until Ready
for dev and Backlog are both empty. Everything below applies to this run
only; a plain `/conveyor:work` afterwards is human-gated again.

1. **Agreement — every run.** AskUserQuestion; the accept option reads:
   "I agree — autonomous run: merge PRs, self-approve specs/plans, file and
   triage issues without asking me." Decline → offer a plain run and stop.
   The agreement in-session is what pre-authorizes the merge writes.
2. **Permissions — once per repo.** If `.claude/settings.json` lacks
   `Bash(gh pr merge:*)` in `permissions.allow`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --grant-auto-merge`.
3. **Dispatch loop.** You are the dispatcher: never orchestrate a card
   yourself, keep only per-card reports in context.
   - `/conveyor:doctor` once at start.
   - Pick the top Ready-for-dev card (rules in step 2 above) → spawn a FRESH
     lead subagent for that one card. Give it: the issue number, the
     conveyor:executing-tasks skill by name, the sentence "This is a
     declared `/conveyor:work auto` run — finish with the Auto-merge step",
     and the report contract: one paragraph — `merged <sha>` or
     `blocked: <reason>`, plus issues filed.
   - Judge the report, tally it, release the lead. Merged → brake counter
     resets; anything else → +1.
   - Ready empty → Backlog triage (step 4), then resume the loop.
   - Stop on: Ready + Backlog both empty, or 3 consecutive no-merge cards
     (brake). Final summary: merged / filed / parked / brake state.
4. **Backlog triage.** Spawn a triage agent: read every open Backlog issue,
   classify each `groomed | needs-spec | human` + one-line reason; report
   only the classification. Dispatcher acts:
   - groomed → `card.sh move <n> ready`
   - human → `card.sh move <n> humanOnly` + `**Unblock:**` comment
   - needs-spec → spawn a spec-lead: write the spec (brainstorming skill
     format; decisions come from the issue + docs, no human Q&A) →
     spec-judge gate → conveyor:writing-plans → plan-judge gate → slice to
     Ready cards. A judge rejection gets one fix round; 2 rejections on the
     same artifact → `card.sh move <n> humanOnly` with the draft linked.
5. **Sources.** Work is read ONLY from Ready for dev and Backlog. Human Only
   is write-only parking — never a work source. Never move any card to Done.
