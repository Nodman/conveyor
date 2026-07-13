# conveyor

A Claude Code plugin that runs my delivery workflow on top of a GitHub
Projects board. Issues go in one end, reviewed and QA'd pull requests come
out the other:

**brainstorm → spec → plan → TDD execution → PR review → QA → human merge**

Install it once, run `/conveyor:init` in any GitHub-connected repo. The
per-repo footprint is a config file and some docs folders — no stack code.

## Why?

I wanted agents worflow with github project baord

Heavily inspired by [Superpowers](https://github.com/obra/superpowers) and does not try to replace it however it is suggested to keep only one of those to skip any conflicts
[Theo's (t3.gg)](https://t3.gg) takes on picking the right model for the job
instead of throwing the biggest one at everything.

## Install

```
/plugin marketplace add Nodman/conveyor
/plugin install conveyor@conveyor-marketplace
/conveyor:init
```

Run `init` once inside each repo you want on the pipeline.

## How a task flows

The board has eight columns:

```
Human Only · Backlog · Ready for dev · In Progress · Agent Review · QA · Done · Archived
```

`/conveyor:work` runs one task through the loop:

1. Pick the highest-priority **Ready for dev** card, move it to **In Progress**.
2. Read the issue and its linked docs. Unclear acceptance criteria? The card
   goes to **Human Only** with an `**Unblock:**` comment instead of guessing.
3. Feature-sized work with no spec gets *brainstorming* and *writing-plans*
   first.
4. An orchestrator spawns fresh implementer subagents per plan task (TDD),
   judging each report against a ledger. Executors run tests and commit; they
   never open PRs.
5. The orchestrator pushes and opens **one** PR (`Fixes #n`, a short
   subsystem-tagged body), then moves the card to **Agent Review**.
6. **pr-reviewer** reviews the diff. Blocking findings go back to the owning
   executor, which fixes and replies in the thread; then a scoped re-review.
   Clean → `approved-by-agent`.
7. **qa-agent** verifies the acceptance criteria on the PR branch (skipped
   for docs-only diffs). Pass → `qa-passed`, the card waits in **QA**;
   fail → back to In Progress.
8. All gates passed → `ready-to-merge` on the PR and issue. **A human
   merges.** The merge closes the issue and board automation moves the card
   to Done. Agents never merge and never set Done by hand — unless you opt
   into an autonomous run (below).

## What `/conveyor:init` does

1. **Preflight** — checks `gh auth`, the `project` token scope, a GitHub
   remote, and `jq`.
2. **Board** — finds a linked project or creates one; an existing project's
   columns get reconciled to the canonical eight. You map each old column
   interactively, and renames keep item values.
3. **Config** — writes `.claude/conveyor.json` (owner, repo, project number,
   field/option ids, labels, policies) and verifies every status key
   resolved.
4. **Scaffold** — seeds `docs/{specs,plans,gotchas}`, the `agent-task` issue
   template, the three labels, and a delimited conveyor block in `CLAUDE.md`.
5. **Project skills** — stubs `.claude/skills/running-the-app` and
   `running-tests` from the detected stack, with `<!-- FILL -->` markers for
   you to complete.
6. **Doctor** — runs `/conveyor:doctor` and offers to commit the scaffolding
   as a PR.

### Board automations you set by hand

Three GitHub Projects workflow automations are not API-settable. `init`
prints this checklist; set them in **Project → ⋯ → Workflows**:

- ✅ Enable **"Item added to project" → Backlog**
- ✅ Enable **"Item closed" → Done**
- 🚫 Keep **"Pull request linked to issue"** *disabled* — it re-moves merged
  cards back to In Progress on late link events.

## `.claude/conveyor.json`

Written by `init`; every script reads it (`CONVEYOR_CONFIG` overrides the
path).

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
  "qaSkipPaths": ["docs/**"]       // advisory: a diff touching only these
                                   //   paths reads as QA n/a
}
```

## Autonomous mode

`/conveyor:auto` drains the board without human gates, for that run only:

- Every run opens with an explicit agreement prompt. The first run also
  grants auto-merge permissions (`Bash(gh pr merge:*)` plus an autoMode rule
  in `.claude/settings.json`).
- A fresh lead subagent per card runs the full lifecycle and squash-merges
  once CI is green and `ready-to-merge` is applied.
- Ready for dev empty → Backlog triage: groomed issues get promoted,
  feature-sized ones get spec'd and planned with **spec-judge** /
  **plan-judge** approval gates (2 rejections → Human Only).
- Human Only is never a work source. Agents still never set Done by hand.
- Brake: 3 consecutive cards without a merge stops the run.

## Model routing

**codex models currently running in a yolo mode, which is not really safe so risk is yours**

Before spawning any subagent, the `routing` skill picks the model: classify
the task (judgment / taste / intel / legwork / review), apply a quality
floor, then take the cheapest model that clears it. Escalation is standing
permission — if a cheap model's output misses the bar, redo with a smarter
one without asking.

The pool isn't Claude-only. If the codex CLI is installed and authenticated,
codex models join the pool and `codex-exec.sh` runs them sandboxed with an
audited log. `/conveyor:council` builds on this: multi-model deliberation on
a hard design question — independent proposals, one rebuttal round, a merged
verdict — then the normal spec flow.

A repo can override the default pool with `.claude/routing.md`.

## Project skills contract

QA is stack-agnostic, so the "how to build/run/test *this* app" knowledge
lives in two per-repo skills that `init` stubs and you complete:

- **`running-the-app`** — build and launch commands, prerequisites, how to
  observe it running, how to read logs.
- **`running-tests`** — full-suite command, single-test command,
  prerequisites, how to read results.

`qa-agent` loads these first. Missing or still containing `<!-- FILL -->`
markers → it reports **BLOCKED** and QA is impossible. `/conveyor:doctor`
flags the same gap.

## Credits

- [Superpowers](https://github.com/obra/superpowers) by Jesse Vincent — the
  brainstorm flow, plan format, TDD-with-review loop, systematic debugging,
  and gotchas all trace back to it.
- [Theo (t3.gg)](https://t3.gg) — the cost-aware model routing idea.

## License

MIT — see [LICENSE](LICENSE).
