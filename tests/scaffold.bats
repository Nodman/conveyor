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

@test "--grant-label-perms creates settings.json with the four allow rules" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | length' "$s")" -eq 4 ]
  [ "$(jq '.permissions.allow | index("Bash(gh pr edit:*)")' "$s")" != "null" ]
  [ "$(jq '.permissions.allow | index("Bash(gh issue edit:*)")' "$s")" != "null" ]
  [ "$(jq '.permissions.allow | index("Bash(gh issue comment:*)")' "$s")" != "null" ]
  [ "$(jq '.permissions.allow | index("Bash(gh issue create:*)")' "$s")" != "null" ]
}

@test "--grant-label-perms is idempotent — re-run adds no duplicates" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.allow | length' "$TMP/.claude/settings.json")" -eq 4 ]
}

@test "--grant-label-perms merges without clobbering, duplicating, or reordering" {
  seed_cfg
  printf '{"permissions":{"allow":["Bash(ls:*)","Bash(gh pr edit:*)"],"deny":["WebFetch"]},"env":{"FOO":"1"}}' \
    > "$TMP/.claude/settings.json"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | length' "$s")" -eq 5 ]
  [ "$(jq -r '.permissions.allow[0]' "$s")" = "Bash(ls:*)" ]
  [ "$(jq -r '.permissions.allow[1]' "$s")" = "Bash(gh pr edit:*)" ]
  [ "$(jq -r '.permissions.deny[0]' "$s")" = "WebFetch" ]
  [ "$(jq -r '.env.FOO' "$s")" = "1" ]
}

@test "--grant-label-perms on the old two rules gains exactly the new two" {
  seed_cfg
  printf '{"permissions":{"allow":["Bash(gh pr edit:*)","Bash(gh issue edit:*)"]}}' \
    > "$TMP/.claude/settings.json"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | length' "$s")" -eq 4 ]
  [ "$(jq -r '.permissions.allow[2]' "$s")" = "Bash(gh issue comment:*)" ]
  [ "$(jq -r '.permissions.allow[3]' "$s")" = "Bash(gh issue create:*)" ]
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
