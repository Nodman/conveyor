# conveyor

A Claude Code plugin that turns any GitHub-connected repo into an agent-driven
delivery pipeline. One board, one lifecycle: **brainstorm → spec → plan → TDD
execution → PR review → QA → human merge** (or autonomous merge in a
`/conveyor:work auto` run). Install once, use in any repo — the
per-repo footprint is config + docs, no stack code shipped.

Board columns, in order:

```
Human Only · Backlog · Ready for dev · In Progress · Agent Review · QA · Done · Archived
```

## Install

```
/plugin marketplace add Nodman/conveyor
/plugin install conveyor@conveyor-marketplace
/conveyor:init
```

`init` is the per-repo setup; run it once inside each repo you want on the pipeline.

## What `/conveyor:init` does

1. **Preflight** — checks `gh auth`, the `project` token scope, a GitHub remote,
   and `jq`; warns if the `superpowers` plugin is still enabled (see below).
2. **Board** — finds a linked project or creates one (`board-create.sh`), or
   reconciles an existing project's columns to the canonical eight
   (`board-reconcile.sh`): you interactively map each existing column to a
   canonical state, and renames preserve item values (matched by option id).
3. **Config** — writes `.claude/conveyor.json` (owner, repo, project number,
   field/option ids, labels, policies) and verifies every status key resolved.
4. **Scaffold** (`scaffold.sh`) — seeds `docs/{specs,plans,gotchas}`, the
   `agent-task` issue template, the `approved-by-agent` / `qa-passed` /
   `ready-to-merge` labels, and
   a delimited conveyor block in `CLAUDE.md`.
5. **Project skills** — generates `.claude/skills/running-the-app` and
   `running-tests` stubs from the detected stack, leaving `<!-- FILL -->` markers
   for you to complete.
6. **Doctor** — runs `/conveyor:doctor` and offers to commit the scaffolding on a
   branch as a PR.

## Manual board automations

Three GitHub Projects workflow automations are **not** API-settable — set them by
hand in the board UI (**Project → ⋯ → Workflows**). `init` prints this checklist:

- ✅ Enable **"Item added to project" → Backlog**
- ✅ Enable **"Item closed" → Done**
- 🚫 Keep **"Pull request linked to issue"** *disabled* — enabling it re-moves
  merged cards back to In Progress on late link events.

## `.claude/conveyor.json`

Written by `init`; every script reads it (`CONVEYOR_CONFIG` overrides the path).

```jsonc
{
  "owner": "acme",                 // GitHub owner (user or org)
  "repo": "widget",                // bare repo name
  "project": 7,                    // project number
  "projectId": "PVT_kwTEST",       // project node id (GraphQL)
  "statusFieldId": "PVTSSF_status",
  "status": {                      // canonical key → { board name, option id }
    "humanOnly":   { "name": "Human Only",    "id": "opt_ho" },
    "backlog":     { "name": "Backlog",       "id": "opt_bl" },
    "ready":       { "name": "Ready for dev", "id": "opt_rd" },
    "inProgress":  { "name": "In Progress",   "id": "opt_ip" },
    "agentReview": { "name": "Agent Review",  "id": "opt_ar" },
    "qa":          { "name": "QA",            "id": "opt_qa" },
    "done":        { "name": "Done",          "id": "opt_dn" },
    "archived":    { "name": "Archived",      "id": "opt_av" }
  },
  "priorityFieldId": "PVTSSF_prio",
  "priority": {                    // P1 > P2 > P3; unset card = P2
    "p1": { "name": "P1", "id": "opt_p1" },
    "p2": { "name": "P2", "id": "opt_p2" },
    "p3": { "name": "P3", "id": "opt_p3" }
  },
  "labels": { "approved": "approved-by-agent", "qaPassed": "qa-passed", "readyToMerge": "ready-to-merge" },
  "mergePolicy": "solo",           // merge is always the human's
  "qaSkipPaths": ["docs/**"]       // advisory input to the orchestrator's QA
                                   //   decision: a diff touching only these paths
                                   //   reads as QA n/a (judgment stays primary)
}
```

## Lifecycle

The definition of *done* for one task (`/conveyor:work` runs the loop):

1. Pick the highest-priority **Ready for dev** card → move it to **In Progress**.
2. Read the issue + its linked docs. Unclear acceptance criteria → move to
   **Human Only** and leave an `**Unblock:**` comment.
3. Feature-sized with no spec → *brainstorming* then *writing-plans* first.
4. The orchestrator spawns fresh implementer subagents per plan task (TDD),
   judging each report against a durable ledger. Executors run tests and commit;
   they **never** open PRs.
5. Orchestrator pushes and opens **one** PR (`Fixes #n` + a ≤6-bullet
   subsystem-tagged body) → moves the card to **Agent Review**.
6. **pr-reviewer** reviews the diff. Blocking findings route back to the owning
   executor, which fixes, pushes, and replies in the comment thread; then a
   scoped re-review. Clean → `approved-by-agent`.
7. **qa-agent** verifies the acceptance criteria on the PR branch (skipped for
   docs-only / `qaSkipPaths` diffs). Pass → `qa-passed`, card stays in **QA**
   as the merge-ready waiting room; fail → back to In Progress.
8. All gates passed → the orchestrator applies `ready-to-merge` to the PR + issue
   and reports the PR as merge-ready. **A human merges** — the merge closes
   the issue and automation moves the card to **Done**. Agents never merge and
   never set Done by hand. In an auto run the orchestrator merges instead — see
   Autonomous mode.

## Autonomous mode

`/conveyor:work auto` drains the board without human gates, for this run only:

- Every run opens with an explicit agreement prompt ("I agree — autonomous
  run: …"); first run also scaffolds `scaffold.sh --grant-auto-merge`
  (adds `Bash(gh pr merge:*)` + an autoMode rule to `.claude/settings.json`).
- Dispatcher pattern: a fresh lead subagent per card runs the full lifecycle
  and squash-merges once CI is green and `ready-to-merge` is applied.
- Ready for dev empty → Backlog triage: groomed issues promoted, feature-sized
  ones spec'd and planned with **spec-judge** / **plan-judge** approval gates
  (2 rejections → Human Only), human-needed ones parked in Human Only.
- Human Only is never a work source. Cards are never moved to Done by agents.
- Brake: 3 consecutive cards without a merge → the run stops and reports.

## Project skills contract

QA is stack-agnostic, so the "how to build/run/test *this* app" knowledge lives in
two per-repo skills that `init` stubs and you complete:

- **`running-the-app`** — build + launch commands, prerequisites, how to observe
  it running, how to read logs.
- **`running-tests`** — the full-suite command, a single-test command,
  prerequisites, how to read results.

`qa-agent` loads these first; if they are missing or still contain `<!-- FILL -->`
markers it reports **BLOCKED** and QA is impossible. `/conveyor:doctor` flags the
same gap.

## Replaces superpowers

conveyor supersedes the `superpowers` plugin — run one or the other, not both.
Superpowers' durable cores (brainstorm flow, plan format, the TDD + per-task
review loop, systematic debugging, gotchas) are kept here in lean form; its
multi-harness scaffolding and anti-rationalization guardrails are dropped. `init`
and `doctor` detect an enabled superpowers plugin and warn you to disable it.

## Development

```
bats tests                                                  # unit + fixture suite
shellcheck plugin/scripts/*.sh plugin/hooks/*.sh tests/helpers/bin/gh tests/live-smoke.sh
RUN_LIVE=1 tests/live-smoke.sh                              # real-gh end-to-end
```

`tests/` replays `gh` through a fixture stub (`tests/helpers/bin/gh`), so the bats
suite never touches the network. `live-smoke.sh` is the exception: with
`RUN_LIVE=1` it creates a throwaway private repo + project, runs the full
board/scaffold/doctor path against them, and tears them down (it prints a manual
cleanup command if the token lacks the `delete_repo` scope). Without `RUN_LIVE=1`
it prints `skipped` and exits 0. CI runs shellcheck + bats on every push.

## License

MIT — see [LICENSE](LICENSE).
