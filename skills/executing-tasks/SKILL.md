---
name: executing-tasks
description: Use to execute an approved plan (or a single board task) end to end — subagent implementation with per-task review, PR, review rotation, QA rotation, merge-ready report.
---

# Executing tasks

You are the orchestrator: sequence, judge, and gate — delegate implementation.
Board state via `${CLAUDE_PLUGIN_ROOT}/scripts/card.sh`; config
`.claude/conveyor.json`.

## Setup

- Board task: `card.sh move <issue> inProgress` the moment you start.
- Ledger: `.conveyor/ledger-<topic>.md` (gitignored). One line per plan task:
  status, commit sha, open questions. Survives compaction — update it after
  EVERY task, read it on resume.
- Branch: create a feature branch; never work on the default branch.

## Per plan task

1. Spawn an implementer subagent, fresh context. Give it: the task text
   verbatim (files, interfaces, steps), the repo's relevant project skills by
   name, the TDD skill, and the report contract: condensed summary — what
   changed, test evidence (command + counts), concerns. Name executors
   stably (`exec-<issue>-<n>`) so review findings can go back to the author.
   Executors run tests and commit; they never open PRs.
2. Judge the report. Ambiguous or load-bearing claims → spot-check yourself
   (run the tests, read the diff). Two failures on the same task → take it
   over inline.
3. Update the ledger. Repeat.

## Ship

1. Push; open ONE PR: title = task, body = `Fixes #<issue>` + ≤6-bullet
   subsystem-tagged summary (first line a bold subsystem tag). The PR body
   becomes the squash commit — write it for the git log.
2. `card.sh move <issue> agentReview`. Spawn **pr-reviewer** (never with a
   cheaper model override). Round 1 = full charter; re-reviews = scoped to
   the fixes + their comment threads (say so in the spawn prompt).
3. Blocking findings: route each to the executor that wrote it (resume by
   name), with path:line + comment id. Executor fixes, pushes, replies in the
   finding's thread with the fix sha. Card back to agentReview; re-spawn
   reviewer.
4. Approved → decide QA applicability: diff has a runtime surface → 
   `card.sh move <issue> qa`, spawn **qa-agent** (PR + issue numbers). No
   runtime surface (docs-only; pure refactor with test coverage) → note
   "QA: n/a (<reason>)" in the PR body and treat as QA-passed.
5. QA fail → findings back to executors (same loop as review, then scoped
   re-review, then QA again). QA pass → report merge-ready to the human:
   PR link + one-line summary + labels present. **A human merges. Never
   merge, never move a card to Done.**

## Along the way

- Human-only blocker (credentials, device, paid account) → post an
  `**Unblock:** <exact action>` comment on the issue, `card.sh move <issue>
  humanOnly`, assign the human, report, stop that task.
- New trap → gotchas skill. Architecture ruling → docs/DECISIONS.md.
- Anything important out of scope → new issue (`gh issue create` with the
  agent-task template); it lands in Backlog.
