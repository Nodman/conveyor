#!/usr/bin/env bats
load helpers/env

# link-agent-skills runs from the repo (or worktree) root; cwd is the root.

seed_tree() {
  mkdir -p "$TMP/.claude/skills/running-tests" "$TMP/.claude/skills/running-the-app"
  printf 'proj skill\n' > "$TMP/.claude/skills/running-tests/SKILL.md"
  printf 'app skill\n' > "$TMP/.claude/skills/running-the-app/SKILL.md"
  printf 'node_modules/\n.agents/\n' > "$TMP/.gitignore"
}

@test "copies plugin and project skills as real dirs, drops .agents/ gitignore line" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  for name in test-driven-development systematic-debugging gotchas worktrees running-tests running-the-app; do
    [ -d "$TMP/.agents/skills/$name" ]
    [ ! -L "$TMP/.agents/skills/$name" ]
  done
  grep -qF 'synced .agents/skills/gotchas' <<<"$output"
  diff -rq "$SCRIPTS/../skills/gotchas" "$TMP/.agents/skills/gotchas"
  [ "$(grep -cxF '.agents/' "$TMP/.gitignore")" -eq 0 ]
  grep -qxF 'node_modules/' "$TMP/.gitignore"
}

@test "idempotent — second run silent" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "source edit resyncs; hand-edited copy overwritten" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  printf 'v2\n' > "$TMP/.claude/skills/running-tests/SKILL.md"
  printf 'hand edit\n' >> "$TMP/.agents/skills/running-the-app/SKILL.md" 2>/dev/null || printf 'hand edit\n' > "$TMP/.agents/skills/running-the-app/SKILL.md"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  grep -qF 'v2' "$TMP/.agents/skills/running-tests/SKILL.md"
  [ "$(grep -cF 'hand edit' "$TMP/.agents/skills/running-the-app/SKILL.md")" -eq 0 ]
}

@test "old symlink replaced by a real copy" {
  seed_tree
  mkdir -p "$TMP/.agents/skills"
  ln -sfn "$SCRIPTS/../skills/gotchas" "$TMP/.agents/skills/gotchas"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/.agents/skills/gotchas" ]
  [ -f "$TMP/.agents/skills/gotchas/SKILL.md" ]
}

@test "unrecognized contributor dir untouched in both modes" {
  seed_tree
  mkdir -p "$TMP/.agents/skills/contrib-skill"
  printf 'theirs\n' > "$TMP/.agents/skills/contrib-skill/SKILL.md"
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 0 ]
  grep -qF 'theirs' "$TMP/.agents/skills/contrib-skill/SKILL.md"
}

@test "check mode: drift flagged, exit 1, nothing written" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 1 ]
  grep -qF 'DRIFT: .agents/skills/test-driven-development missing or stale' <<<"$output"
  grep -qF 'DRIFT: .agents/ still gitignored' <<<"$output"
  [ ! -e "$TMP/.agents" ]
  grep -qxF '.agents/' "$TMP/.gitignore"
}

@test "check mode: clean tree exits 0 silently" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no project skills dir and no .gitignore — plugin skills still copy, no .gitignore created" {
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TMP/.agents/skills/test-driven-development" ]
  [ ! -e "$TMP/.gitignore" ]
}
