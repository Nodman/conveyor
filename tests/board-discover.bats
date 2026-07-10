#!/usr/bin/env bats
load helpers/env

@test "discover maps present options and nulls missing ones" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover" \
    run "$SCRIPTS/board-discover.sh" acme 7
  [ "$status" -eq 0 ]
  [ "$(jq -r '.status.backlog.id' <<<"$output")" = "opt_bl" ]
  [ "$(jq -r '.status.qa' <<<"$output")" = "null" ]
  [ "$(jq -r '.priorityFieldId' <<<"$output")" = "null" ]
}

@test "discover --find returns linked project number" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/discover" \
    run "$SCRIPTS/board-discover.sh" --find acme widget
  [ "$output" = "7" ]
}
