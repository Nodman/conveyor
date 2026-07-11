#!/usr/bin/env bats

REPO="$BATS_TEST_DIRNAME/.."

frontmatter_ok() { # $1 = file
  local f="$1" close fm
  [ "$(head -n1 "$f")" = "---" ] || { echo "no opening --- in $f"; return 1; }
  close=$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR; exit}' "$f")
  [ -n "$close" ] || { echo "no closing --- in $f"; return 1; }
  fm=$(sed -n "2,$((close - 1))p" "$f")
  grep -q '^name:' <<<"$fm" || { echo "no name: in frontmatter of $f"; return 1; }
  grep -q '^description:' <<<"$fm" || { echo "no description: in frontmatter of $f"; return 1; }
}

no_blockers() { # $1 = file — case-sensitive, fixed-string
  local f="$1" lit
  for lit in Nodman cooqa PVT_; do
    if grep -Fq "$lit" "$f"; then echo "portability blocker '$lit' in $f"; return 1; fi
  done
}

@test "both agent files exist" {
  [ -f "$REPO/plugin/agents/pr-reviewer.md" ]
  [ -f "$REPO/plugin/agents/qa-agent.md" ]
}

@test "every agent and skill file has valid frontmatter and no portability blockers" {
  cd "$REPO"
  local found=0 f
  for f in plugin/agents/*.md plugin/skills/*/SKILL.md; do
    [ -e "$f" ] || continue
    found=1
    frontmatter_ok "$f"
    no_blockers "$f"
  done
  [ "$found" -eq 1 ]
}

@test "prefix rule, human-required policy, and consent gate present in prose" {
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/agents/pr-reviewer.md"
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/agents/qa-agent.md"
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '**[team-lead]**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '**Human required:**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '--grant-label-perms' "$REPO/plugin/skills/init/SKILL.md"
  grep -qF -- '--grant-label-perms' "$REPO/plugin/skills/doctor/SKILL.md"
  grep -qF -- 'set-visibility' "$REPO/plugin/skills/init/SKILL.md"
  grep -qF -- 'set-visibility' "$REPO/plugin/skills/doctor/SKILL.md"
}

@test "qa-passed removal-on-invalidation defined for PR and issue" {
  grep -qF -- '--remove-label qa-passed' "$REPO/plugin/agents/qa-agent.md"
  grep -qF -- '--remove-label qa-passed' "$REPO/plugin/skills/executing-tasks/SKILL.md"
}

@test "ready-to-merge apply and invalidation owned by the orchestrator" {
  grep -qF -- '--add-label ready-to-merge' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '--remove-label ready-to-merge' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  # no agent touches the label — orchestrator is the sole owner (decisive grep last, per bats gotcha)
  ! grep -rqF -- '-label ready-to-merge' "$REPO/plugin/agents/"
}

@test "executing-tasks Setup states the per-issue worktree policy" {
  f="$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- 'git fetch origin' "$f"
  grep -qF -- 'refs/remotes/origin/HEAD' "$f"
  grep -qF -- 'git check-ignore' "$f"
  grep -qF -- 'git worktree add .claude/worktrees/' "$f"
  grep -qF -- 'git worktree remove' "$f"
}

@test "judge agents exist, prefix their comments, and never edit" {
  for f in "$REPO/plugin/agents/spec-judge.md" "$REPO/plugin/agents/plan-judge.md"; do
    [ -f "$f" ]
    grep -qF -- 'never edit' "$f"
  done
  grep -qF -- '**[spec-judge]**' "$REPO/plugin/agents/spec-judge.md"
  grep -qF -- '**[plan-judge]**' "$REPO/plugin/agents/plan-judge.md"
}

@test "auto skill owns the auto-mode contract; work skill stays merge-free" {
  f="$REPO/plugin/skills/auto/SKILL.md"
  grep -qF -- 'I agree' "$f"
  grep -qF -- '--grant-auto-merge' "$f"
  grep -qF -- 'never a work source' "$f"
  grep -qF -- '3 consecutive' "$f"
  grep -qF -- 'spec-judge' "$f"
  grep -qF -- 'plan-judge' "$f"
  grep -qF -- 'conveyor:auto' "$REPO/plugin/skills/work/SKILL.md"
  ! grep -qF -- 'gh pr merge' "$REPO/plugin/skills/work/SKILL.md"
}

@test "executing-tasks defines the auto-merge step" {
  f="$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- 'gh pr merge <n> --squash --delete-branch' "$f"
  grep -qF -- 'gh pr checks' "$f"
  grep -qF -- 'declared auto run' "$f"
}

@test "council skill contract" {
  f="$REPO/plugin/skills/council/SKILL.md"
  [ -f "$f" ]
  grep -qF -- 'codex-exec.sh' "$f"
  grep -qF -- 'read-only' "$f"
  grep -qF -- '<runner>-<model>' "$f"
  grep -qF -- 'session-id' "$f"
  # resume is always by explicit id (decisive grep last, per bats gotcha)
  ! grep -qF -- '--last' "$f"
}
