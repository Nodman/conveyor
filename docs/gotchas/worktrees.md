# Worktrees

## Shell cwd persists — a `cd` into a worktree leaks into later commands
Symptom: `git checkout` / `rebase` / `push` silently operate on the wrong checkout — e.g. `checkout main` runs inside a feature worktree, moving IT to main while the repo root stays on the feature branch (hit 2026-07-11 while rebasing PR #44).
Cause: the Bash tool's working directory persists across calls; one verification command that `cd`s into a worktree redirects every later bare `git` call there.
Rule: never bare-`cd` into a worktree mid-flow — address it per command with `git -C <worktree-path>` (or a subshell `(cd … && …)`), and start any branch-mutating command with an explicit `cd <repo-root> &&`.
