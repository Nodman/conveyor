---
name: work
description: Use when the human says "work on the project / pick up the next task". Picks the top Ready-for-dev card and runs the full lifecycle.
---

# /conveyor:work

1. `/conveyor:doctor` first; surface drift before starting.
2. Pick: `${CLAUDE_PLUGIN_ROOT}/scripts/board-items.sh queue ready` → TSV
   `number<TAB>priority<TAB>title`, number-ascending → highest Priority first
   (P1 > P2 > P3; unset = P2); ties → first row (lowest number = oldest).
   Tell the user what you picked and why.
3. `gh issue view <n>` + every linked doc. Acceptance criteria unclear or
   human decision needed → comment on the issue, move to humanOnly with an
   `**Unblock:**` comment, pick the next card.
4. New-feature-sized and no spec exists → conveyor:brainstorming →
   conveyor:writing-plans first. Groomed task with clear criteria → straight
   to conveyor:executing-tasks.
5. Definition of done = executing-tasks' merge-ready report. Repeat from
   step 2 only if the human asked for continuous pickup.
6. Autonomous runs (no human gates, auto-merge) are a separate skill —
   conveyor:auto. Never run auto behavior from this skill.
