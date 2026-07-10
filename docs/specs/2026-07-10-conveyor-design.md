# Conveyor — design spec

Date: 2026-07-10. Status: approved by brainstorm, pending final review.

## What

Conveyor is a Claude Code plugin that turns any GitHub-connected repo into an
agent-driven delivery pipeline: GitHub Projects board + brainstorm → spec → plan →
TDD execution → PR review → QA → human merge. Extracted and generalized from the
workflow that evolved in `cooqa-swift`; replaces the `superpowers` plugin.

## Why

- The cooqa workflow works but is hardwired: owner/project/field ids duplicated in
  CLAUDE.md, pr-reviewer.md, board-doctor.sh, issue template. Lanes and agents are
  Swift-specific.
- Superpowers (~5,500 lines) carries multi-harness scaffolding and anti-rationalization
  guardrails a top-tier orchestrator does not need. Its durable cores (brainstorm flow,
  plan format, TDD loop, per-task review + ledger, systematic debugging) are worth
  keeping in lean form.
- Goal: one plugin, installed once, usable in any repo; per-repo footprint = config +
  data only.

## Decisions (locked in brainstorm)

- **Packaging**: Claude Code plugin in its own public repo (`~/repos/conveyor`,
  GitHub `Nodman/conveyor`). The repo is its own marketplace source. No official
  marketplace publishing.
- **Superpowers**: full replacement. Init + doctor detect an enabled superpowers
  plugin and warn to disable it.
- **Agents**: no stack specialists shipped or generated. Two generic agents only
  (pr-reviewer, qa-agent). All stack/repo knowledge lives in **project skills**
  (`.claude/skills/` of the target repo) that generic agents self-select.
- **QA**: runs on the PR branch, after review approval, before human merge. Scope:
  verify the issue/spec acceptance criteria end-to-end by driving the real app, plus
  a quick smoke of adjacent flows. How to drive the app comes from project skills.
- **Human Only column**: triage bucket + mid-flight escape. Any card needing human
  action goes there, always with a comment stating the exact unblock action.
- **Gotchas**: protocol ships as a plugin skill; data stays in `docs/gotchas/<category>.md`
  + README index in each repo. Agent picks or creates the category.
- **Docs conventions**: exactly four surfaces — `docs/specs/`, `docs/plans/`,
  `docs/DECISIONS.md`, `docs/gotchas/`. No CHANGELOG/PROGRESS/status docs; history =
  squash-commit bodies (≤6-bullet subsystem-tagged PR body rule kept).
- **Audience**: public repo; solo-first but must work with multiple humans
  (maintainers merge; Human Only cards assigned + @mentioned).
- **No `commands/` dir**: legacy mechanism. init/doctor/work ship as user-invocable
  skills (`/conveyor:init`, `/conveyor:doctor`, `/conveyor:work`).
- **Brainstorm gate kept**: every human work request starts with the lean brainstorming
  skill; effort scales with task size, the gate itself does not disappear.

## Board model

Canonical columns, in order:

**Human Only · Backlog · Ready for dev · In Progress · Agent Review · QA · Done · Archived**

- Pipeline reads left-to-right Backlog → Done. Off-pipeline states sit at the edges:
  Human Only far left (human attention queue), Archived far right (trash).
- **Human Only**: entered at triage or mid-flight. Card must carry an unblock comment;
  in multi-human repos, assigned + @mentioned. Human moves it back when unblocked.
- **Backlog**: default landing for new issues (board automation). Not dev-ready.
- **Ready for dev**: groomed, pickable. Pickup = highest Priority first (P1 > P2 > P3,
  unset = P2).
- **In Progress**: agent working. Card moves here the moment work starts.
- **Agent Review**: PR open, pr-reviewer loop. Approval = `approved-by-agent` label.
- **QA**: entered after review approval. qa-agent verifies the PR branch.
  - Pass → `qa-passed` label; card stays in QA until a human merges (the merge-ready
    waiting room). Merge closes the issue → automation moves card to Done.
  - Fail → findings posted, card back to In Progress, fixes by the executor, then a
    scoped pr-reviewer re-review, then QA again. QA never bypasses review.
  - Applicability: orchestrator decides per PR. No runtime surface (docs-only, pure
    refactor with test coverage) → skip QA with "QA: n/a (reason)" in the PR body.
  - Merge-ready = `approved-by-agent` + (`qa-passed` or stated QA-n/a).
- **Done**: automation only (issue closed by merged PR). Never moved manually.
- **Archived**: human decision; agents may suggest.
- **Lane labels retired.** Decomposition (domain → UI → tests) lives in the plan,
  not in agent identities or issue labels.
- Board automations required but not API-settable (printed as a manual checklist by
  init): "Item added → Backlog" on, "Item closed → Done" on, "Pull request linked to
  issue" **off**.

## Plugin anatomy

```
conveyor/
  .claude-plugin/plugin.json        # + marketplace.json (repo as install source)
  skills/
    brainstorming/        # lean: Q&A one-at-a-time → design sections w/ approval →
                          #   spec to docs/specs/YYYY-MM-DD-<topic>.md → self-review →
                          #   user gate → writing-plans
    writing-plans/        # lean: spec → TDD task list → docs/plans/YYYY-MM-DD-<topic>.md
    executing-tasks/      # subagent-driven execution: per-task implementer → task
                          #   reviewer → fix loop; durable ledger; board card moves;
                          #   PR with Fixes #n + ≤6-bullet body; absorbs
                          #   finishing-a-branch
    test-driven-development/  # red-green-refactor core; enforcement theater cut
    systematic-debugging/     # kept near as-is
    gotchas/              # consult before touching an area; record new traps
    init/                 # /conveyor:init — bootstrap (below)
    doctor/               # /conveyor:doctor — drift checks (below)
    work/                 # /conveyor:work — pick top Ready-for-dev card, run lifecycle
  agents/
    pr-reviewer.md        # generic review gate, pinned top-tier model, never downgraded;
                          #   board ids from conveyor.yml; repo law from CLAUDE.md +
                          #   project skills; inline reviews, approved-by-agent label
    qa-agent.md           # generic; verifies acceptance criteria by driving the real
                          #   app via project skills; reports conclusions, not pixels
                          #   (pattern from cooqa's sim-ui-tester)
  hooks/
    SessionStart          # short: working principles (think-first, simplicity-first,
                          #   surgical changes, goal-driven; from cooqa AGENTS.md) +
                          #   brainstorm gate + pointer to conveyor.yml and lifecycle
    PreToolUse            # guard on CLAUDE.md/AGENTS.md edits: no status/history
                          #   appended; route to PR body / gotchas / DECISIONS.md
  scripts/                # bash + gh + GraphQL, parameterized by conveyor.yml:
                          #   board-create, board-reconcile, ids-discover, card-move,
                          #   board-doctor
  templates/              # agent-task.yml issue template, conveyor.yml, docs scaffold,
                          #   project-skill stubs (run-app, run-tests)
  tests/                  # bats + stubbed gh; opt-in live smoke
  docs/specs/ docs/plans/ docs/gotchas/ docs/DECISIONS.md   # dogfooded
```

- **Skills carry process, never ids.** Board ids exist only in the target repo's
  `conveyor.yml`.
- **Model routing** ships as default policy in skills (executors on a capable model,
  pr-reviewer pinned top-tier, exploration on cheap models), overridable in
  `conveyor.yml`. Replaces the user-scoped CLAUDE.md routing table (user deletes that
  manually — out of scope here).

## Per-repo footprint (created by init)

```
.claude/conveyor.yml               # owner, repo, project number, field/option ids,
                                   #   labels, model policy, merge policy, optional
                                   #   QA-applicability notes (e.g. "docs/** = no QA")
.claude/skills/…                   # project skills (maintainer-provided; init generates
                                   #   run-app / run-tests stubs from stack inspection)
.github/ISSUE_TEMPLATE/agent-task.yml   # Goal, Acceptance criteria, Docs/files, Notes.
                                        #   No Lane dropdown.
docs/specs/  docs/plans/  docs/gotchas/  docs/DECISIONS.md
CLAUDE.md                          # conveyor-managed delimited block only (below)
```

### CLAUDE.md / AGENTS.md conflict policy

- Init manages only a delimited block: `<!-- conveyor:begin -->` …
  `<!-- conveyor:end -->`. Existing CLAUDE.md → block appended; re-init replaces block
  content only, idempotent. No CLAUDE.md → minimal file with just the block.
- AGENTS.md is never created or edited.
- Init runs a **conflict scan** of existing CLAUDE.md/AGENTS.md and reports (never
  edits) overlaps: competing lifecycle/board instructions, superpowers references,
  contradicting process rules. Doctor re-checks marker integrity.

## /conveyor:init flow (interactive)

1. Preflight: `gh` installed + authed, `project` scope, GitHub remote exists,
   superpowers enabled → warn.
2. Board: find a project linked to the repo. None → create via GraphQL (columns +
   Priority field). Exists → reconcile: show existing columns, ask the human to map
   them to canonical states, create missing options (Status options are API-editable).
3. Print manual checklist: the three board automations (not API-settable).
4. Discover all ids → write `.claude/conveyor.yml`.
5. Scaffold docs dirs, issue template, CLAUDE.md block; run conflict scan; report.
6. Inspect stack → generate project-skill stubs → ask user to review them.
7. Finish with a doctor run.

## /conveyor:doctor checks

- Cooqa's four drift rules: open-issue card in Done; closed issue outside
  Done/Archived; Agent Review card without an open closing PR; In Progress card with
  an open closing PR.
- New: QA card without an `approved-by-agent` PR; Human Only card without an unblock
  comment; `conveyor.yml` ids stale vs live board; superpowers still enabled; expected
  labels missing; CLAUDE.md marker block broken.

## Task lifecycle (the generic ritual, encoded in work/executing-tasks skills)

1. Pick from Ready for dev (highest priority) → move card to In Progress.
2. Read issue + linked spec/plan/docs; consult gotchas skill.
3. Feature-sized work: brainstorming → spec → plan first (specs/plans committed).
   Board issues map to plan tasks for multi-PR work.
4. Execute with TDD (tests first where applicable), subagent-driven, durable ledger.
5. Open PR: `Fixes #n`, ≤6-bullet subsystem-tagged body → move card to Agent Review.
6. pr-reviewer loop: findings → executor fixes → thread replies → scoped re-review.
7. Approval → move to QA → qa-agent (or stated QA-n/a).
8. QA pass → `qa-passed`; report merge-ready. A human merges; automation → Done.
9. New traps → gotchas; rulings → DECISIONS.md; follow-ups → new issues (land in
   Backlog; groom to Ready for dev + Priority if dev-ready).

## Testing

- **bats-core** for every script, with a stubbed `gh` on PATH replaying recorded
  fixtures. Coverage: board create from nothing; reconcile against a foreign board
  (missing/renamed columns); id discovery; conveyor.yml round-trip; every doctor rule
  (one failing fixture each); card moves; CLAUDE.md block idempotency.
- **Opt-in live smoke** (`RUN_LIVE=1`): scratch repo + project via real `gh`, full
  init, assert board shape + config, teardown. Manual, pre-release only.
- **CI on conveyor repo**: GitHub Actions, bats + shellcheck per PR. Target repos need
  no CI.
- **Skills/agents**: short verify checklist per skill, exercised during dogfooding.
  No subagent pressure-testing harness.

## Milestones

1. Repo skeleton + plugin manifest.
2. Scripts + bats harness (TDD from the start).
3. Skills (lean rewrites), agents, hooks, templates.
4. init / doctor / work skills.
5. Live smoke green.
6. **Dogfood: install into cooqa-swift** (exercises the reconcile path — the board
   already exists). This is the v1 acceptance test.
7. **Self-host**: run `/conveyor:init` on the conveyor repo itself; all further
   conveyor development flows through its own board. (Bootstrap exception: work before
   this milestone uses spec/plan discipline but no board.)

## cooqa-swift migration (after milestone 6)

- Run init → reconcile existing board → `.claude/conveyor.yml`.
- Delete all five `.claude/agents/*`:
  - sim-ui-tester → project skill `driving-the-simulator` (bundle id, simulator MCP
    mechanics, log reading) consumed by generic qa-agent.
  - swift-ui/data/test specialists → project skills carrying their project-specific
    rules; executors become generic agents + skills.
  - pr-reviewer → plugin's generic one.
- CLAUDE.md: replace lifecycle/board/ids/routing sections with the conveyor block;
  keep domain rules, locked decisions, design digests. AGENTS.md: remove the
  role/working-principles section (now in the plugin hook).
- Move `docs/superpowers/{specs,plans}` → `docs/{specs,plans}`.
- Delete `Scripts/board-doctor.sh`; regenerate issue template (no Lane); remove
  `lane:*` labels.
- Disable superpowers for the project.
- Flag (user does manually): delete routing table from user-scoped ~/.claude/CLAUDE.md.

## Out of scope

- Editing the user's global ~/.claude/CLAUDE.md.
- Official marketplace publishing.
- CI/automation inside target repos.
- Multi-harness support (Claude Code only).
