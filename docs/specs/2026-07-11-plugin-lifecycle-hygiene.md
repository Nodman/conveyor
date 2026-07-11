# Plugin lifecycle hygiene: label permissions, human-required policy, comment prefixes, self-update

## What

Four small plugin changes (all in `plugin/`; this repo consumes them by updating itself):

1. Plugin ships the permission rules agents need to apply lifecycle labels — with explicit user consent.
2. A hybrid policy for human-required follow-up actions discovered mid-lifecycle.
3. Every agent-written PR/issue comment is prefixed with the writing agent's name.
4. The self-hosting update flow (this repo dogfoods its own plugin) is documented.

## Why

- QA agents on PR #16/#17 were classifier-blocked adding `qa-passed`; relaying the action is
  permission laundering. Lifecycle stalls on a label no agent can write.
- Human-required cleanups (scratch repo deletion) lived only in chat + gitignored ledgers — lost
  if the session dies.
- PR threads mix comments from reviewer, executors, QA with no attribution.
- Plugin source changes here don't affect running sessions (cache 0.1.0) — flow was undocumented.

## Decisions (locked)

- Permissions land in the target repo's `.claude/settings.json` (checked in), narrowest expressible
  prefix rules: `Bash(gh pr edit:*)`, `Bash(gh issue edit:*)`.
- **Consent gate:** `scaffold.sh` never touches settings by default. New explicit flag
  (`--grant-label-perms`); the init/doctor skill must first tell the user "about to modify
  `.claude/settings.json` permissions: <exact rules> because <reason>" and get a yes
  (AskUserQuestion). No silent permission edits, ever.
- Human-required follow-ups: hybrid. Merge-time actions → one `**Human required:**` checklist
  comment on the PR (orchestrator posts/updates it). Missing-scope/credential work or anything
  outliving the PR → Human Only card + `**Unblock:**` comment + human assignee.
- Comment prefix: `**[<agent-name>]**` (e.g. `**[exec-2-1]**`, `**[reviewer-pr17]**`); orchestrator
  uses `**[team-lead]**`. Applies to every PR/issue comment an agent writes.
- Self-update: any PR touching `plugin/` bumps `plugin.json` patch version. After merge, human runs
  `claude plugin marketplace update conveyor-marketplace && claude plugin update conveyor`.
  Running sessions keep the old cache until restart. Not automated (chicken-and-egg).

## Design

### 1. Label permissions (scaffold.sh + init/doctor skills)
- `scaffold.sh --grant-label-perms`: jq-merge `{"permissions":{"allow":["Bash(gh pr edit:*)","Bash(gh issue edit:*)"]}}`
  into `.claude/settings.json` (create if missing, dedupe, idempotent; respects `--dry-run`).
- init skill: after board setup, ask the user (exact rules + reason shown); yes → run with flag,
  no → skip and note labels stay manual.
- doctor skill: session-level check — rules absent → report as finding with the consent question,
  never auto-fix.

### 2. Human-required policy (executing-tasks skill + agent charters)
- executing-tasks: new "Human-required follow-ups" section with the hybrid rule; orchestrator owns
  posting the PR checklist comment / creating the Human Only card.
- qa-agent.md, pr-reviewer.md: human-required items go in the final report (structured), never
  chat-only; the orchestrator routes them per policy.

### 3. Comment prefixes (agent charters + executing-tasks)
- pr-reviewer.md, qa-agent.md: prefix rule + example.
- executing-tasks: executor spawn contract includes the prefix rule; orchestrator's own comments
  use `**[team-lead]**`.

### 4. Self-update docs (repo-level)
- CLAUDE.md (this repo, outside the conveyor marker block): plugin-dev section — version-bump rule
  + the two update commands.
- docs/DECISIONS.md entry for the hybrid policy and consent gate.

### Testing
- bats: scaffold `--grant-label-perms` creates/merges/dedupes settings.json; without flag → file
  untouched; `--dry-run` prints, writes nothing.
- bats: charter/skill files contain the prefix rule and policy markers (structure test).
- Suite green + shellcheck clean (running-tests skill).

## Out of scope

- Automating the plugin update from inside a session.
- Backfilling prefixes/labels on merged PRs #16/#17.
- Broader permission grants (repo create/delete, project mutations) — QA scratch flows stay as-is.
