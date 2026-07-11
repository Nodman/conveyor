#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }

@test "find prints item id and current status" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' find 41"
  [ "$status" -eq 0 ]
  [ "$output" = $'PVTI_41\tReady for dev' ]
}

@test "find exits 3 when no card exists" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' find 99"
  [ "$status" -eq 3 ]
}

@test "move edits the item and prints confirmation" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' move 41 inProgress"
  [ "$status" -eq 0 ]
  [ "$output" = "moved #41 → In Progress" ]
  run grep -F "item-edit" "$GH_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--single-select-option-id opt_ip"* ]]
  [[ "$output" == *"--id PVTI_41"* ]]
}

@test "move with unknown status key fails" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' move 41 bogus"
  [ "$status" -ne 0 ]
}

@test "unknown subcommand shows usage" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' frobnicate 41"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage:"* ]]
}

@test "item-list at the 200 cap WARNs on stderr, find stdout preserved" {
  use_cfg
  mkdir -p "$TMP/fix"
  jq -n '{items: [range(1;201) | {id: "PVTI_\(.)", content: {number: .}, status: "Ready for dev"}]}' \
    > "$TMP/fix/project_item-list.out"
  GH_FIX="$TMP/fix" run --separate-stderr bash -c "cd '$TMP' && '$SCRIPTS/card.sh' find 41"
  [ "$status" -eq 0 ]
  [ "$output" = $'PVTI_41\tReady for dev' ]
  [[ "$stderr" == *"WARN: gh project item-list returned 200 == limit — results may be truncated"* ]]
}
