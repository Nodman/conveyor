# Adopt superpowers worktree skill — plan

Spec: `docs/specs/2026-07-16-adopt-superpowers-worktrees.md` (judge-approved).

**Goal:** one vendored skill becomes the single worktree source of truth;
worktree dir moves `.claude/worktrees/` → `.worktrees/`.

**Architecture:** new plugin skill `worktrees` = conveyor declarations
(precedence over body) + verbatim upstream body with two marked edits.
executing-tasks shrinks to a pointer. scaffold/board-doctor/link-agent-skills
learn the new dir. Repo migrates in the same PR.

**Global constraints (from spec):**
- Upstream pin: `obra/superpowers@d00f4ad4428e99db18619e077b99340fb7158f2f`,
  file `skills/using-git-worktrees/SKILL.md`, MIT, attributed.
- Body verbatim except exactly two `<!-- conveyor edit -->` sites.
- Precedence rule = first line of declarations section.
- New worktrees: `.worktrees/<branch>` at repo root. R10 scans new + legacy.
- This PR leaves codex able to see the skill (symlink regime today: run
  `link-agent-skills.sh`, nothing to commit; if #91's copy regime landed
  first: commit `.agents/skills/worktrees/`).
- Patch bump `plugin/.claude-plugin/plugin.json` (current source 0.1.33; use
  current+1 at implementation time).
- bats: mid-test assertions use `[ ]`/`grep`, decisive `[[ ]]` only as last
  command (docs/gotchas/bats.md).

## File map

| File | Responsibility |
|---|---|
| `plugin/skills/worktrees/SKILL.md` (new) | vendored skill + declarations |
| `plugin/skills/worktrees/upstream.md` (new) | pristine upstream copy — fidelity reference |
| `tests/structure.bats` | new skill assertions; executing-tasks worktree test updated |
| `plugin/scripts/scaffold.sh` | gitignore append `.worktrees/` |
| `tests/scaffold.bats` | path updates |
| `plugin/scripts/board-doctor.sh` | R10 dual-path scan |
| `tests/fixtures/doctor-worktree-orphan/git_worktree_list.out` | add `.worktrees/` orphan entry |
| `tests/board-doctor.bats` | assert new-path orphan flagged |
| `plugin/scripts/link-agent-skills.sh` | `worktrees` in PLUGIN_LIST |
| `tests/link-agent-skills.bats` | loop list gains `worktrees` |
| `plugin/skills/executing-tasks/SKILL.md` | worktree block → pointer |
| `docs/DECISIONS.md` | ruling entry |
| `.gitignore` | add `.worktrees/` (legacy line stays) |
| `plugin/.claude-plugin/plugin.json` | patch bump |

Spec's "grant-auto-merge.md + gotchas/worktrees.md updated" maps to Task 6's
stale-path verification: neither file contains a worktree-path string today
(checked), so "updated" = proven current by grep, not edited.

## Task 1 — vendor the skill

Files: `plugin/skills/worktrees/SKILL.md` (new), `tests/structure.bats`.
Produces for later tasks: skill name `worktrees`, path
`plugin/skills/worktrees/SKILL.md`.

- [ ] Append to `tests/structure.bats`:

```bash
@test "worktrees skill: vendored body + conveyor declarations" {
  f="$REPO/plugin/skills/worktrees/SKILL.md"
  [ -f "$f" ]
  grep -qF -- 'obra/superpowers' "$f"
  grep -qF -- 'd00f4ad4428e99db18619e077b99340fb7158f2f' "$f"
  grep -qF -- '.worktrees/<branch>' "$f"
  grep -qF -- 'Verify Clean Baseline' "$f"
  grep -qF -- 'running-tests' "$f"
  # exactly two edit markers in the vendored body (preamble mentions the
  # literal too — count the body only)
  [ "$(sed -n '/^# Using Git Worktrees$/,$p' "$f" | grep -cF -- '<!-- conveyor edit -->')" -eq 2 ]
  # precedence rule opens the declarations section
  grep -A3 -F -- '## Conveyor declarations' "$f" | grep -qF -- 'overrides the copied body'
  # body fidelity: minus the two marker lines, byte-identical to upstream
  diff <(sed -n '/^# Using Git Worktrees$/,$p' "$f" | grep -vF -- '<!-- conveyor edit -->') \
       <(sed -n '/^# Using Git Worktrees$/,$p' "$REPO/plugin/skills/worktrees/upstream.md")
}
```

Fidelity mechanics: `plugin/skills/worktrees/upstream.md` = the fetched file
committed byte-for-byte unmodified. Each conveyor edit is exactly ONE
physical line starting with `<!-- conveyor edit -->` (Edit 2's paragraph is
written as one long line), so stripping marker lines re-produces the
upstream body from `# Using Git Worktrees` down and `diff` exits 0.

- [ ] Run `bats tests/structure.bats` — new test fails (file missing).
- [ ] Fetch and commit the reference:
  `curl -sL https://raw.githubusercontent.com/obra/superpowers/d00f4ad4428e99db18619e077b99340fb7158f2f/skills/using-git-worktrees/SKILL.md -o plugin/skills/worktrees/upstream.md`
  — byte-for-byte, no edits ever.
- [ ] Create `plugin/skills/worktrees/SKILL.md` = frontmatter + preamble +
  declarations below, then upstream.md's body from `# Using Git Worktrees`
  down verbatim, then insert the two single-line edits.

Frontmatter + preamble + declarations (exact content):

```markdown
---
name: worktrees
description: Use when starting any work that needs an isolated checkout — before executing plans, per-issue executor worktrees, or ad-hoc isolation. Detect existing isolation, then native tools, then git worktree fallback.
---

# Worktrees

Vendored from obra/superpowers `using-git-worktrees` (MIT), commit
d00f4ad4428e99db18619e077b99340fb7158f2f. The body below "Using Git
Worktrees" is verbatim upstream except two `<!-- conveyor edit -->` sites.
To update: re-fetch upstream, re-apply the marked edits.

## Conveyor declarations

Precedence: in conveyor-orchestrated runs (executing-tasks, auto, direct
fixes on board cards) this section overrides the copied body wherever they
conflict — including EVERY native-tool-preference statement (Step 1a, Step
1b's "only if no native tool" guard, Quick Reference, Common Mistakes, Red
Flags). The body's native-tool preference applies only to solo ad-hoc
isolation outside the lifecycle.

- Dir: `.worktrees/<branch>` at the repo root. One worktree per issue;
  branch cut from `origin/<default>` after `git fetch origin` (default via
  `git symbolic-ref --short refs/remotes/origin/HEAD`, strip `origin/`;
  fallback `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`).
- Orchestrated per-issue worktrees ALWAYS use the git path (Step 1b) —
  codex `--workdir`, fix-round reuse, and the merge step need one stable
  shared path. Never native tools for these.
- No consent question inside the lifecycle — isolation is mandated.
- The body's `cd "$path"` is for solo sessions. Conveyor agents address the
  worktree per command — `git -C <path>` or a subshell
  (docs/gotchas/worktrees.md: cwd leaks; two-writer sweeps).
- Lifecycle: reuse the worktree across fix rounds; one write-mode codex per
  worktree; once all gates pass, `git worktree remove` it BEFORE the merge
  (a branch checked out in a worktree can't be `--delete-branch`d).
- Baseline (Steps 2–3): use the repo's `running-tests` project skill when
  present; the body's autodetect is the fallback. Record deps + baseline
  result in the ledger. Red baseline → stop and report; never proceed
  silently.
```

Edit 1 — directly under the `### 1a. Native Worktree Tools (preferred)`
heading, insert one line:

```markdown
<!-- conveyor edit --> Skipped in conveyor lifecycle runs — see Conveyor declarations.
```

Edit 2 — directly after the body paragraph
`**If \`GIT_DIR != GIT_COMMON\` (and not a submodule):** You are already in a linked worktree. Skip to Step 2 (Project Setup). Do NOT create another worktree.`
insert:

```markdown
<!-- conveyor edit --> Conveyor runs: reuse is keyed to BRANCH identity,
linked worktrees only. Issue branch checked out in a linked worktree
(`git worktree list --porcelain`, entries after the first/primary) → use it
at its existing path (legacy `.claude/worktrees/` paths stay valid until
they drain). Inside a DIFFERENT issue's worktree → resolve the main checkout
via `git rev-parse --git-common-dir` and create/reuse the issue worktree
from there — never nest, never hijack. Issue branch checked out in the
PRIMARY checkout → blocking violation: stop, `**Unblock:**` comment +
humanOnly; never write there, never auto-switch the user's checkout.
```

(Shown wrapped for readability — write it as ONE physical line, same for
Edit 1, or the fidelity diff in the structure test fails.)

- [ ] `bats tests/structure.bats` — passes.
- [ ] Commit: `feat(worktrees): vendor superpowers using-git-worktrees with conveyor declarations`

## Task 2 — scaffold writes `.worktrees/`

Files: `plugin/scripts/scaffold.sh`, `tests/scaffold.bats`.

- [ ] In `tests/scaffold.bats` replace every `.claude/worktrees/` with
  `.worktrees/` (4 tests: add, idempotent, no-trailing-newline, dry-run
  untouched — dry-run test has no path literal, verify).
- [ ] `bats tests/scaffold.bats` — path tests fail.
- [ ] In `plugin/scripts/scaffold.sh` replace all FOUR `.claude/worktrees/`
  literals with `.worktrees/`: grep guard (L79), skip message (L80), say
  line (L82), printf (L85). Verify none left:
  `grep -c 'claude/worktrees' plugin/scripts/scaffold.sh` → 0.
- [ ] `bats tests/scaffold.bats` — passes.
- [ ] Commit: `feat(scaffold): gitignore .worktrees/ (new worktree dir)`

## Task 3 — R10 scans both dirs

Files: `plugin/scripts/board-doctor.sh`,
`tests/fixtures/doctor-worktree-orphan/git_worktree_list.out`,
`tests/board-doctor.bats`.

- [ ] Append to `tests/fixtures/doctor-worktree-orphan/git_worktree_list.out`
  (mirrors existing blocks; same `pr_list.out` stub returns no PRs):

```
worktree /repo/.worktrees/fix-10-stale
HEAD dddddddddddddddddddddddddddddddddddddddd
branch refs/heads/fix/10-stale
```

- [ ] Append to `tests/board-doctor.bats` after the R10 space test:

```bash
@test "R10 flags orphans under the new .worktrees/ dir too" {
  use_cfg
  run_doctor doctor-worktree-orphan
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphaned worktree /repo/.worktrees/fix-10-stale"* ]]
}
```

- [ ] `bats tests/board-doctor.bats` — new test fails (path filtered out).
- [ ] `plugin/scripts/board-doctor.sh` line 143:

```bash
    case "$wpath" in */.worktrees/*|*/.claude/worktrees/*) ;; *) continue ;; esac
```

  Update the R10 comment (line 137) to name both dirs.
- [ ] `bats tests/board-doctor.bats` — passes (existing legacy tests prove
  the old dir still scanned).
- [ ] Commit: `feat(doctor): R10 scans .worktrees/ and legacy .claude/worktrees/`

## Task 4 — codex sees the skill

Files: `plugin/scripts/link-agent-skills.sh`, `tests/link-agent-skills.bats`.

- [ ] In `tests/link-agent-skills.bats`, first test's `for name in` list:
  add `worktrees` →
  `for name in test-driven-development systematic-debugging gotchas worktrees running-tests running-the-app; do`
- [ ] `bats tests/link-agent-skills.bats` — fails (no link made).
- [ ] `plugin/scripts/link-agent-skills.sh` line 9:
  `PLUGIN_LIST=(test-driven-development systematic-debugging gotchas worktrees)`
- [ ] `bats tests/link-agent-skills.bats` — passes.
- [ ] Ship per live mechanism: script still symlinks (this branch) → run
  `plugin/scripts/link-agent-skills.sh` from the worktree root, commit
  nothing. If #91's copy version merged first (script does `cp -R`): rebase,
  run it, `git add .agents/skills/worktrees` and amend this task's commit.
- [ ] Commit: `feat(codex): sync worktrees skill into .agents/skills`

## Task 5 — executing-tasks points at the skill

Files: `plugin/skills/executing-tasks/SKILL.md`, `tests/structure.bats`.
Consumes: skill name `worktrees` (Task 1).

- [ ] In `tests/structure.bats` replace the body of
  `@test "executing-tasks Setup states the per-issue worktree policy"`:

```bash
@test "executing-tasks Setup states the per-issue worktree policy" {
  f="$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- 'plugin/skills/worktrees/SKILL.md' "$f"
  grep -qF -- '.worktrees/<branch>' "$f"
  grep -qF -- 'git worktree remove' "$f"
  ! grep -qF -- '.claude/worktrees/' "$f"
}
```

- [ ] `bats tests/structure.bats` — fails.
- [ ] In `plugin/skills/executing-tasks/SKILL.md` replace the Setup worktree
  bullet (lines 18–31) with:

```markdown
- Worktree: load the `conveyor:worktrees` skill
  (plugin/skills/worktrees/SKILL.md) and follow it — one per issue at
  `.worktrees/<branch>`, cut from `origin/<default>`; reuse across fix
  rounds; deps + test baseline recorded in the ledger; `git -C <path>`/
  subshell, never bare-`cd` (docs/gotchas/worktrees.md); once all gates
  pass, `git worktree remove` it before the merge.
```

- [ ] Nothing else in that file references `.claude/worktrees/` (verify:
  `grep -n '.claude/worktrees' plugin/skills/executing-tasks/SKILL.md` → empty).
- [ ] `bats tests/structure.bats` — passes.
- [ ] Commit: `refactor(executing-tasks): worktree policy delegated to worktrees skill`

## Task 6 — repo migration + ruling + version

Files: `.gitignore`, `docs/DECISIONS.md`, `plugin/.claude-plugin/plugin.json`.
TDD n/a (config/docs) — verification steps inline.

- [ ] `.gitignore`: add line `.worktrees/`; KEEP `.claude/worktrees/` (two
  live legacy worktrees drain on merge).
- [ ] `docs/DECISIONS.md`, new entry at top:

```markdown
## 2026-07-16 — Worktree policy vendored from superpowers

- Chose vendoring obra/superpowers `using-git-worktrees` (pinned commit,
  two marked edits, precedence-rule declarations) over reinventing — user
  ruling: upstream is battle-tested.
- Worktree dir is now `.worktrees/<branch>` (upstream convention); legacy
  `.claude/worktrees/` stays valid until existing worktrees drain (R10
  scans both).
- New: deps install + clean test baseline before work, recorded in the
  ledger; red baseline stops the task.
- Single source of truth: `plugin/skills/worktrees/SKILL.md`;
  executing-tasks only points at it.
```

- [ ] Bump `plugin/.claude-plugin/plugin.json` patch (current+1).
- [ ] Verify: `bats tests/` full suite green (running-tests skill).
- [ ] Verify: `grep -rn 'claude/worktrees' plugin/ docs/gotchas/
  plugin/templates/` → exactly two intentional legacy sites: board-doctor.sh
  R10 (pattern + comment) and the worktrees skill's Edit 2 (legacy-path
  reuse rule). Anything else — including any hit in docs/gotchas/ or
  templates — is a miss; fix it.
- [ ] Commit: `chore(worktrees): repo migration to .worktrees/, ruling, version bump`

## Board mapping

Single-PR plan → one agent-task issue for the card, then
conveyor:executing-tasks. PR body: `Fixes #<issue>` + ≤6-bullet summary.
