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
- Worktree: load the `conveyor:worktrees` skill
  (plugin/skills/worktrees/SKILL.md) and follow it — one per issue at
  `.worktrees/<branch>`, cut from `origin/<default>`; reuse across fix
  rounds; deps + test baseline recorded in the ledger; `git -C <path>`/
  subshell, never bare-`cd` (docs/gotchas/worktrees.md); once all gates
  pass, `git worktree remove` it before the merge.

## Per plan task

1. Load `plugin/skills/routing/SKILL.md` first; pick the model per its
   procedure; record the route (class, floor, model, reason) in the spawn
   prompt. Then spawn an implementer subagent, fresh context. Give it: the
   task text verbatim (files, interfaces, steps), the repo's relevant project
   skills by name, the TDD skill, and the report contract: condensed summary —
   what changed, test evidence (command + counts), concerns. Include the
   comment-prefix rule: every PR/issue comment starts with the author's name
   — `**[<agent-name>]**` (e.g. `**[claude-opus-4-8--12-1]** Fixed in
   abc123.`). Name executors `<runner>-<model>--<issue>-<n>` (e.g.
   `claude-opus-4-8--12-1`, `codex-gpt-5.6-sol--12-1`) so review findings can
   go back to the author; claude Agent names never contain dots; ALWAYS set
   `model:` explicitly. Claude executors run tests and commit; they never open
   PRs.

   Codex lane (route = codex): spawn via
   `${CLAUDE_PLUGIN_ROOT}/scripts/codex-exec.sh
   run --workdir <issue worktree> --name
   codex-<model>--<issue>-<n> --model <model> --out <report> --output-schema
   ${CLAUDE_PLUGIN_ROOT}/config/report.schema.json --prompt-file <f>`; the
   prompt file carries the task text verbatim, output bar, report contract,
   comment-prefix rule, style rule, the instruction to follow the
   `test-driven-development` skill (TDD is mandatory for codex the same as
   for claude executors), and the commit-identity rule (commit with
   `git -c user.name=<agent-name> -c user.email=codex@conveyor.invalid commit`
   plus `Conveyor-Model: <model>` and `Conveyor-Session: <session-id>`
   trailers). Codex runs full-access in its own dedicated per-issue worktree
   (never a shared checkout): it edits, runs ANY tests, commits under that
   identity, and pushes its own feature branch. Sentinel wait:
   `codex-exec.sh wait <out> --timeout 540`, re-call while `status` shows
   `running`; `dead` → `codex-exec.sh kill <out>`, then resume by session id
   (`codex-exec.sh session-id <log>`). Fix
   rounds resume by session id, one targeted repair max, then escalate per
   routing. One write-mode codex per worktree at a time. Codex
   missing/throttled → routing fallback (Opus) + ledger note.
2. Judge the report. Ambiguous or load-bearing claims → spot-check yourself
   (run the tests, read the diff). Two failures on the same task → take it
   over inline.
3. Update the ledger. Repeat.

## Ship

1. Claude lane: before pushing, judge proportionally — rerun the load-bearing
   tests and skim the diff stat/scope; deep-read only on suspicion (the review
   gate is the one deep read per PR). Then push. Codex lane: codex already
   pushed its own branch. Open ONE PR: title = task, body = `Fixes #<issue>` +
   ≤6-bullet subsystem-tagged summary (first line a bold subsystem tag). The PR
   body becomes the squash commit — write it for the git log. After ANY push
   (any lane), wait for CI before the card advances: `gh pr checks <n> --watch`;
   red checks → treat as a blocking finding, route to the executor.
2. `card.sh move <issue> agentReview`. Spawn the review gate per routing (never
   a cheaper model override; never the PR's sole-author family). A claude gate
   runs **pr-reviewer**; a codex gate runs via `codex-exec.sh run` and
   posts its own review + labels directly under its `**[<agent-name>]**`
   prefix. Round 1 =
   full charter; re-reviews = scoped to the fixes + their comment threads (say
   so in the prompt).
3. Blocking findings: route each to the executor that wrote it (resume by name
   / codex session id), with path:line + comment id. The executor fixes, runs
   tests, commits, pushes, and replies in the finding's thread with the fix sha
   under its own name (codex resumes by session id and fixes/pushes in its
   worktree). After any push, wait for CI (`gh pr checks <n> --watch`). Card
   back to agentReview; route the re-review to the SAME reviewer (resume by
   name — it keeps round-1 context); spawn fresh with the scoped prompt only if
   it's gone.
4. Approved → decide QA applicability (your judgment is primary): diff has a
   runtime surface → `card.sh move <issue> qa`, spawn **qa-agent** (PR + issue
   numbers). No runtime surface (docs-only; pure refactor with test coverage;
   or every changed path matches `qaSkipPaths` in `.claude/conveyor.json`) →
   note "QA: n/a (<reason>)" in the PR body, treat as QA-passed, and apply
   `ready-to-merge` (`gh pr edit <n> --add-label ready-to-merge` and
   `gh issue edit <issue> --add-label ready-to-merge`).
5. QA fail → findings back to executors (same loop as review, then scoped
   re-review, then QA again). QA pass → apply `ready-to-merge`
   (`gh pr edit <n> --add-label ready-to-merge` and `gh issue edit <issue>
   --add-label ready-to-merge`), then report merge-ready to the human:
   PR link + one-line summary + labels present. `ready-to-merge` is the
   orchestrator's alone — no subagent applies it. **Plain runs: a human merges — never merge.
   Declared auto runs (the session declared /conveyor:auto): run the Auto-merge step
   below. Never move a card to Done in any mode.**
6. **Commits after a QA pass invalidate it** — new commits pushed after
   `qa-passed` → remove it and `ready-to-merge` (`gh pr edit <n>
   --remove-label qa-passed --remove-label ready-to-merge` and `gh issue edit
   <issue> --remove-label qa-passed --remove-label ready-to-merge`) and re-run
   QA.

## Auto-merge step (declared auto runs only)

Runs after `ready-to-merge` is applied; every earlier gate is unchanged.

1. Preconditions: `gh pr checks <n>` all green, and no unresolved
   `**Human required:**` checklist on the PR. Either fails → `card.sh move
   <issue> humanOnly` + `**Unblock:**` comment, report `blocked`, stop.
2. Merge conflict → rebase inside the issue worktree (`git -C <path>`,
   docs/gotchas/worktrees.md), `git push --force-with-lease`. The push
   invalidates `qa-passed` (rule above) → re-run QA → retry the merge once;
   second failure → humanOnly as in step 1.
3. `git worktree remove` the issue worktree first — all gates have passed, so
   it is no longer needed, and a branch checked out in a worktree can't be
   `--delete-branch`d. Then run
   `gh pr merge <n> --squash --delete-branch`. `Fixes #<issue>` closes the
   issue; board automation moves the card to Done — never move it yourself.
   Report `merged <sha>`.

## Human-required follow-ups

Agents never sit on a human action or relay a denied write to another agent —
they report it; the orchestrator routes it:

- Doable at merge time on that PR (apply a label, run a one-liner) → maintain
  ONE PR comment starting `**[team-lead]** **Human required:**` with a
  checklist; update it in place, never post duplicates.
- Needs scopes/credentials agents lack, or outlives the PR → agent-task
  issue, `card.sh move <n> humanOnly`, `**Unblock:** <exact command>`
  comment, assign the human.
- Chat-only is not tracking: no PR comment or card → it doesn't exist.

## Team hygiene

Spawned teammates hold terminal panes; too many live at once and new spawns
fail. Release agents at their **terminal state**, not on idle:

- Release (shutdown_request) an agent once **no in-flight work item can route
  back to it**: an executor only after its PR clears review AND its findings
  are fixed+verified (a ledger entry alone is not release — the PR gate is);
  a reviewer after its PR's rotation ends in approval.
- Until then it STAYS alive — blocking findings route to the SAME executor,
  and scoped re-reviews reuse the reviewer's round-1 context.
- Shutting down loses nothing durable: the ledger, report files, and each
  finding's text (path:line + comment id + defect) persist — a fresh spawn
  handles a late fix from those alone.
- A spawn failing with a pane/fork error usually means this: release finished
  agents and retry.

## Along the way

- Human-only blocker (credentials, device, paid account) → post an
  `**Unblock:** <exact action>` comment on the issue, `card.sh move <issue>
  humanOnly`, assign the human, report, stop that task.
- New trap → gotchas skill. Architecture ruling → docs/DECISIONS.md.
- Anything important out of scope → new issue (`gh issue create` with the
  agent-task template); it lands in Backlog.
