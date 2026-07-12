# Worktrees

## Shell cwd persists — a `cd` into a worktree leaks into later commands
Symptom: `git checkout` / `rebase` / `push` silently operate on the wrong checkout — e.g. `checkout main` runs inside a feature worktree, moving IT to main while the repo root stays on the feature branch (hit 2026-07-11 while rebasing PR #44).
Cause: the Bash tool's working directory persists across calls; one verification command that `cd`s into a worktree redirects every later bare `git` call there.
Rule: never bare-`cd` into a worktree mid-flow — address it per command with `git -C <worktree-path>` (or a subshell `(cd … && …)`), and start any branch-mutating command with an explicit `cd <repo-root> &&`.

## Two executors in one worktree: `git add` sweeps the other's uncommitted edits
Symptom: executor A's commit silently bundles executor B's in-progress uncommitted changes (hit 2026-07-12, PR #60: the printf fix commit swept the unrelated test-gating fix; B's planned commit message was lost from history).
Cause: fix rounds route findings to multiple executors that share the one-per-issue worktree; `git add`-all + commit takes whatever is in the tree.
Rule: serialize fix rounds in a shared worktree — the orchestrator dispatches one executor at a time (or executors commit ONLY their exact files via `git add <paths>`); never rewrite pushed history to fix attribution afterward — the squash merge erases it anyway.
