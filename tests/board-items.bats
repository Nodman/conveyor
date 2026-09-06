#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }

@test "find prints item id and status, ignores other projects" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 0 ]
  [ "$output" = $'PVTI_41\tReady for dev' ]
}
@test "find exits 3 when no item belongs to this project" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card-miss" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 3 ]
}
@test "find dies non-3 on API failure" {
  use_cfg
  mkdir -p "$TMP/nofix"
  GH_FIX="$TMP/nofix" run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CardItem query failed"* ]]
}
