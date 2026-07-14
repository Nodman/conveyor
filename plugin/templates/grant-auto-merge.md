<!-- conveyor:grant:auto-merge -->
### Auto-run grant (written by scaffold --grant-auto-merge)

During a declared /conveyor:auto run the human has agreed, via the per-run
agreement prompt, to autonomous operation: squash-merging PRs that carry
the ready-to-merge label (gh pr merge --squash --delete-branch) and
judge-agent self-approval of specs and plans. Outside a declared auto run,
merging PRs stays human-only. Moving cards to Done is never
agent-performed — board automation owns it.

Codex write lane: codex-exec.sh run (danger-full-access, the script
default) inside per-issue worktrees — full file and network access (codex edits,
tests, commits, pushes) and local environment visibility. This grant is
written only by scaffold --grant-auto-merge, which conveyor runs only
after the human accepts the /conveyor:auto agreement prompt that names
codex full access. Applies in declared /conveyor:auto runs and in
human-gated sessions.
