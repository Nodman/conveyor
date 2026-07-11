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
}
