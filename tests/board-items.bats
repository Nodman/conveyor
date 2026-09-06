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

@test "queue emits number-ascending TSV across pages, empty priority for unset" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 0 ]
  [ "$output" = $'12\tP1\ttwelve\n25\t\ttwenty five\n30\tP2\tthirty' ]
}
@test "queue passes the status name in the server-side filter" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 0 ]
  run grep -F 'status:"Ready for dev"' "$GH_LOG"
  [ "$status" -eq 0 ]
}
@test "queue dies on API failure" {
  use_cfg
  mkdir -p "$TMP/nofix"
  GH_FIX="$TMP/nofix" run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 1 ]
  [[ "$output" == *"QueueItems query failed"* ]]
}

@test "scan emits issue JSON lines, skips drafts, keeps null status" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items/scan-ok" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' scan"
  [ "$status" -eq 0 ]
  [ "$output" = '{"number":10,"status":"Ready for dev","state":"OPEN"}
{"number":11,"status":"Done","state":"CLOSED"}
{"number":12,"status":"","state":"OPEN"}' ]
}
@test "scan dies on partial GraphQL errors" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items/scan-errors" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ScanItems: GraphQL errors in response"* ]]
}
@test "scan dies when fetched count != totalCount" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items/scan-mismatch" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fetched 4 != totalCount 6"* ]]
}
