# Adopt superpowers worktree skill — spec

User ruling 2026-07-16: copy, don't reinvent — upstream is battle-tested.

## What

New plugin skill `conveyor:worktrees` = near-verbatim copy of
obra/superpowers `using-git-worktrees` (MIT, attributed) + a conveyor
declarations section. All living worktree directives across plugin/docs
point at it. Worktree dir moves `.claude/worktrees/` → `.worktrees/`.

## Why

- Worktree handling is scattered across executing-tasks, scaffold,
  board-doctor, templates, gotchas — drift caused repeated incidents
  (PRs #44, #60, branch-switching #85/#87/#89).
- Upstream skill adds what conveyor lacks: isolation detection order,
  native-tool preference, deps install, clean test baseline before work.

## Decisions (locked)

- **Skill:** `plugin/skills/worktrees/SKILL.md`. Upstream steps verbatim:
  detect (git-dir ≠ common-dir + submodule guard) → native tool → git
  fallback → deps install → baseline tests. Header attributes
  obra/superpowers (MIT).
- **Conveyor declarations** (prepended section, uses upstream's own
  "instruction-declared preference" hooks):
  - Dir: `.worktrees/<branch>` at repo root. One worktree per issue,
    branch cut from `origin/<default>` after `git fetch`.
  - Orchestrated per-issue worktrees ALWAYS use the git path, never
    native tools — codex `--workdir`, fix-round reuse, and merge need one
    stable shared path. Native tools valid for solo ad-hoc isolation only.
  - **Precedence rule** (first line of the declarations section): in
    conveyor-orchestrated runs this section overrides the copied body
    wherever they conflict — explicitly including EVERY native-tool-
    preference statement (Step 1a, Step 1b's "only if no native tool"
    guard, the Critical Rules never/always lists). The body stays
    verbatim; no sentence-by-sentence patching.
  - **Declared edits to the copied body** (the only two, each marked
    `<!-- conveyor edit -->` inline): (1) Step 1a gains "skipped in
    conveyor lifecycle runs — see declarations". (2) Step 0 reuse is
    keyed to BRANCH IDENTITY, not path — LINKED worktrees only: issue
    branch already checked out in a linked worktree (`git worktree list
    --porcelain`, entries other than the first/primary) → use it at its
    existing path (git forbids double-checkout; relocation is churn —
    legacy `.claude/worktrees/` paths keep working until they drain).
    Issue branch checked out in the PRIMARY checkout → blocking
    violation: stop and report (lifecycle runs: `**Unblock:**` comment +
    humanOnly); never write there, never auto-switch the user's checkout. Inside a DIFFERENT issue's worktree → resolve the main
    checkout via `git rev-parse --git-common-dir`, create/reuse the issue
    worktree from there — never nest, never hijack. `.worktrees/` governs
    where NEW worktrees are created, never a reason to move existing
    ones.
  - No consent question inside the conveyor lifecycle — isolation is
    mandated.
  - Upstream's `cd "$path"` is for solo sessions; conveyor agents use
    `git -C`/subshell (docs/gotchas/worktrees.md).
  - Lifecycle: reuse across fix rounds; one write-mode codex per
    worktree; `git worktree remove` before merge.
  - Baseline: use the repo's `running-tests` project skill when present;
    upstream autodetect is fallback. Record result in the ledger. Red
    baseline → stop, report; never proceed silently.
- **executing-tasks SKILL.md:** worktree block (Setup) shrinks to "load
  `conveyor:worktrees`, one per issue" + lifecycle-only bits; all
  `.claude/worktrees/` refs → `.worktrees/`.
- **scaffold.sh:** gitignore append becomes `.worktrees/`.
- **board-doctor.sh R10:** scans `.worktrees/` AND legacy
  `.claude/worktrees/` (live legacy worktrees drain on merge).
- **Codex sync:** add `worktrees` to `link-agent-skills.sh` sources, then
  RUN the script in this PR and ship its output under whichever mechanism
  is live at land time: symlink regime → local links only (gitignored,
  nothing to commit); copy regime (#91 landed first) → commit
  `.agents/skills/worktrees/` copies. If #91 lands second, its migration
  run picks `worktrees` up from the sources list. Either order works —
  the rule is: this PR leaves codex able to see the skill.
- **Docs updated:** grant-auto-merge.md template, docs/DECISIONS.md
  ruling, docs/gotchas/worktrees.md path examples (both traps stay).
  Historical specs/plans untouched.
- **This repo migrates in the same PR:** `.gitignore` gains `.worktrees/`;
  legacy line stays until old worktrees drain.
- Patch bump `plugin/.claude-plugin/plugin.json`.

## Testing

- bats: scaffold appends `.worktrees/` (idempotent); R10 flags orphans in
  both dirs; link-agent-skills syncs `worktrees` skill.
- Skill text is doc — exercised by the next real issue's execution flow.

## Out of scope

- Pruning/moving existing legacy worktrees.
- Auto-resync from upstream superpowers.
- Changing harness `EnterWorktree` behavior.
- Rewriting historical specs/plans.
