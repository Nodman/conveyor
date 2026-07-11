#!/usr/bin/env bats
load helpers/env

# scaffold runs from the target repo root; config is read from .claude/conveyor.json in cwd.
seed_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }

@test "scaffold creates dirs, renders template + block, creates labels" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TMP/docs/specs" ]
  [ -d "$TMP/docs/plans" ]
  [ -d "$TMP/docs/gotchas" ]
  [ -f "$TMP/docs/DECISIONS.md" ]
  [ -f "$TMP/docs/gotchas/README.md" ]
  grep -q 'acme/7' "$TMP/.github/ISSUE_TEMPLATE/agent-task.yml"
  ! grep -qi 'Lane' "$TMP/.github/ISSUE_TEMPLATE/agent-task.yml"
  grep -q 'acme/7' "$TMP/CLAUDE.md"
  grep -q 'conveyor:begin' "$TMP/CLAUDE.md"
  [ "$(grep -c 'label create' "$GH_LOG")" -eq 2 ]
}

@test "pre-existing docs/DECISIONS.md is not overwritten" {
  seed_cfg
  mkdir -p "$TMP/docs"
  printf 'KEEPME\n' > "$TMP/docs/DECISIONS.md"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh'"
  [ "$status" -eq 0 ]
  grep -q 'KEEPME' "$TMP/docs/DECISIONS.md"
  [[ "$output" == *"skip docs/DECISIONS.md"* ]]
}

@test "--dry-run prints [dry-run] lines and writes nothing" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -d "$TMP/docs" ]
  [ ! -d "$TMP/.github" ]
  [ ! -f "$TMP/CLAUDE.md" ]
  [ ! -s "$GH_LOG" ]
}

@test "--grant-label-perms creates settings.json with the two allow rules" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.allow | length' "$TMP/.claude/settings.json")" -eq 2 ]
  run jq -r '.permissions.allow[]' "$TMP/.claude/settings.json"
  [[ "$output" == *"Bash(gh pr edit:*)"* ]]
  [[ "$output" == *"Bash(gh issue edit:*)"* ]]
}

@test "--grant-label-perms merges without clobbering, duplicating, or reordering" {
  seed_cfg
  printf '{"permissions":{"allow":["Bash(ls:*)","Bash(gh pr edit:*)"],"deny":["WebFetch"]},"env":{"FOO":"1"}}' \
    > "$TMP/.claude/settings.json"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.allow | length' "$TMP/.claude/settings.json")" -eq 3 ]
  [ "$(jq -r '.permissions.allow[0]' "$TMP/.claude/settings.json")" = "Bash(ls:*)" ]
  [ "$(jq -r '.permissions.deny[0]' "$TMP/.claude/settings.json")" = "WebFetch" ]
  [ "$(jq -r '.env.FOO' "$TMP/.claude/settings.json")" = "1" ]
}

@test "without --grant-label-perms settings.json is untouched" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh'"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/.claude/settings.json" ]
}

@test "--grant-label-perms respects --dry-run" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --dry-run --grant-label-perms"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -e "$TMP/.claude/settings.json" ]
}
