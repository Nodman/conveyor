#!/usr/bin/env bats
load helpers/env

# link-agent-skills runs from the repo (or worktree) root; cwd is the root.

seed_tree() {
  mkdir -p "$TMP/.claude/skills/running-tests" "$TMP/.claude/skills/running-the-app"
  printf 'node_modules/\n' > "$TMP/.gitignore"
}

@test "links plugin practice skills and project skills into .agents/skills" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  for name in test-driven-development systematic-debugging gotchas running-tests running-the-app; do
    [ -L "$TMP/.agents/skills/$name" ]
    [ -d "$TMP/.agents/skills/$name" ]
  done
  grep -qxF '.agents/' "$TMP/.gitignore"
}

@test "idempotent — second run reports nothing new" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(grep -cxF '.agents/' "$TMP/.gitignore")" -eq 1 ]
}

@test "check mode: clean tree exits 0 silently" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check mode: missing links and gitignore entry flagged, exit 1, nothing written" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 1 ]
  grep -qF 'DRIFT: .agents/skills/test-driven-development' <<<"$output"
  grep -qF 'DRIFT: .agents/ not gitignored' <<<"$output"
  [ ! -e "$TMP/.agents" ]
  ! grep -qxF '.agents/' "$TMP/.gitignore"
}

@test "check mode: stale link (wrong target) flagged" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  ln -sfn "$TMP" "$TMP/.agents/skills/gotchas"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 1 ]
  [[ "$output" == *"DRIFT: .agents/skills/gotchas"* ]]
}

@test "run repairs a stale link" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  ln -sfn "$TMP" "$TMP/.agents/skills/gotchas"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  grep -q 'SKILL.md' <<<"$(ls "$TMP/.agents/skills/gotchas/")"
}

@test "no project skills dir — plugin skills still link" {
  printf '' > "$TMP/.gitignore"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -L "$TMP/.agents/skills/test-driven-development" ]
}

@test "no .gitignore — one is created with the entry" {
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  grep -qxF '.agents/' "$TMP/.gitignore"
}
