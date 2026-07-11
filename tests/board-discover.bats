#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

@test "discover maps present options and nulls missing ones" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover" \
    run "$SCRIPTS/board-discover.sh" acme 7
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status.backlog.id' <<<"$output")" = "opt_bl" ]
  [ "$(jq -r '.status.qa' <<<"$output")" = "null" ]
  [ "$(jq -r '.priorityFieldId' <<<"$output")" = "null" ]
}

@test "discover --find returns linked project number, no warning" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover" \
    run --separate-stderr "$SCRIPTS/board-discover.sh" --find acme widget
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
  [ -z "$stderr" ]
}

@test "discover --find falls back to title match with WARN" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover-titlematch" \
    run --separate-stderr "$SCRIPTS/board-discover.sh" --find acme widget
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
  [[ "$stderr" == *WARN* ]]
}

@test "discover --find no match exits 3" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover-nomatch" \
    run "$SCRIPTS/board-discover.sh" --find acme widget
  [ "$status" -eq 3 ]
}
