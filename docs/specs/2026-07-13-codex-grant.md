# Codex full-access grant — fold into --grant-auto-merge

Issue: #75

## What

`scaffold.sh --grant-auto-merge` also pre-authorizes the codex write lane, so
auto runs can spawn `codex-exec.sh run --sandbox danger-full-access` without
the auto-mode classifier blocking it. One flag = the whole auto bundle.

## Why

- The auto grant bundle predates the codex yolo lane: full-access spawns are
  "never named as allowed", so the classifier denies them (observed live).
- The session cannot self-edit settings.json to fix it — that is
  guard-weakening self-modification, correctly blocked. The grant must come
  from a human-gated scaffold run, same consent pattern as auto-merge and
  label perms (DECISIONS 2026-07-11).

## Decisions (locked)

- Fold into `--grant-auto-merge` (user-chosen over a separate flag): one
  explicit yes covers merge + judges + codex write lane. Existing repos
  re-run the grant once.
- permissions.allow rule uses a version-wildcarded path — docs confirm `*`
  matches at any position in Bash rules. Derived from the script's own
  location, so it survives plugin updates.
- autoMode.allow sentence names the exact risk: full access (no sandbox) in
  per-issue worktrees, network + commit/push, and local environment
  visibility. Honest consent, per the 2026-07-13 yolo ruling.
- Auto skill agreement prompt adds codex full-access to the accept text.
- Only `run` is granted; `preflight`/`detect`/`audit`/etc. stay
  prompt-gated (read-only, cheap to approve manually when needed).

## Design

`plugin/scripts/scaffold.sh`, in the `grant_auto` block:

- Resolve the rule path from `$here` (the running script's dir):
  - matches `*/.claude/plugins/cache/*` → replace the version segment with
    `*`: `Bash(<cache>/<marketplace>/<plugin>/*/scripts/codex-exec.sh run:*)`
  - otherwise (repo dogfood run) → literal `Bash($here/codex-exec.sh run:*)`
- permissions.allow += that rule (dedup, same jq pattern as the merge rule).
- autoMode.allow += new sentence:
  "The user has explicitly pre-authorized conveyor's codex write lane:
  running codex-exec.sh run with --sandbox danger-full-access inside
  per-issue worktrees. This grants codex full file and network access (it
  edits, tests, commits, pushes) and visibility of the local environment.
  Applies in declared /conveyor:auto runs and in human-gated sessions."

`plugin/skills/auto/SKILL.md`:

- Step 1 accept option text gains "spawn codex full-access": "I agree —
  autonomous run: merge PRs, self-approve specs/plans, spawn codex
  full-access, file and triage issues without asking me."
- Step 2 grant check also looks for the codex rule (substring
  `codex-exec.sh run`) — missing → run `--grant-auto-merge` (idempotent).

`plugin/.claude-plugin/plugin.json`: patch bump (0.1.26 if #72/#74 land
first; next free patch otherwise).

Tests:

- `tests/scaffold.bats`: extend the grant-auto-merge case — settings.json
  gains the codex rule (wildcarded path asserted) and the autoMode sentence
  (`danger-full-access` substring); re-run stays idempotent (no dupes).
- `tests/structure.bats` auto-contract test: accept text mentions codex.

## Out of scope

- Any change to codex-exec.sh itself or its sandbox modes.
- Granting non-`run` subcommands.
- The manual-session permission prompt for first-time codex use in repos
  that never ran the grant (that prompt is correct).
