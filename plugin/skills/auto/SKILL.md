---
name: auto
description: Use ONLY when the human explicitly invokes /conveyor:auto — an autonomous run that drains Ready for dev + Backlog with no human gates: fresh lead per card, judge-approved specs/plans, auto-merge. Opens with a per-run agreement prompt.
---

# /conveyor:auto

An autonomous run: no human gates until Ready for dev and Backlog are both
empty. Everything here applies to this run only; a plain `/conveyor:work`
afterwards is human-gated again.

1. **Agreement — every run.** AskUserQuestion; the accept option reads:
   "I agree — autonomous run: merge PRs, self-approve specs/plans, file and
   triage issues without asking me." Decline → offer a plain run and stop.
   The agreement in-session is what pre-authorizes the merge writes.
2. **Permissions — once per repo.** If `.claude/settings.json` lacks
   `Bash(gh pr merge:*)` in `permissions.allow` OR lacks the auto-run rule
   in `autoMode.allow`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --grant-auto-merge` (it is
   idempotent — when in doubt, run it).
3. **Card pick rules.** `/conveyor:doctor` first; surface drift before
   starting. Pick: `gh project item-list <project> --owner <owner> --limit
   200 --format json` → open issues in "Ready for dev", highest Priority
   first (P1 > P2 > P3; unset = P2); ties → oldest.
4. **Dispatch loop.** You are the dispatcher: never orchestrate a card
   yourself, keep only per-card reports in context.
   - Pick the top Ready-for-dev card (rules in step 3) → spawn a FRESH lead
     subagent for that one card. Give it: the issue number, the
     conveyor:executing-tasks skill by name, the sentence "This is a
     declared `/conveyor:auto` run — finish with the Auto-merge step", and
     the report contract: one paragraph — `merged <sha>` or `blocked:
     <reason>`, plus issues filed.
   - Judge the report, tally it, release the lead. Merged → brake counter
     resets; anything else → +1.
   - Ready empty → Backlog triage (step 5), then resume the loop.
   - Stop on: Ready + Backlog both empty, or 3 consecutive no-merge cards
     (brake). Final summary: merged / filed / parked / brake state.
5. **Backlog triage.** Spawn a triage agent: read every open Backlog issue,
   classify each `groomed | needs-spec | human` + one-line reason; report
   only the classification. Dispatcher acts:
   - groomed → `card.sh move <n> ready`
   - human → `card.sh move <n> humanOnly` + `**Unblock:**` comment
   - needs-spec → spawn a spec-lead: write the spec (brainstorming skill
     format; decisions come from the issue + docs, no human Q&A) →
     spec-judge gate → conveyor:writing-plans → plan-judge gate. On
     approval, place the work: single-PR plan → move the ORIGINAL issue to
     Ready with the spec/plan linked in a comment (it becomes the work
     card); multi-PR plan → file one issue per slice, comment the slice
     links on the original, then close the original as superseded (board
     automation moves it to Done — you never move the card yourself). A
     judge rejection gets one fix round; 2 rejections on the same artifact →
     `card.sh move <n> humanOnly` with the draft linked.
6. **Sources.** Work is read ONLY from Ready for dev and Backlog. Human Only
   is write-only parking — never a work source. Never move any card to Done.
