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
