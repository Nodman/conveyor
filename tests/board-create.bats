#!/usr/bin/env bats
load helpers/env

@test "board-create creates, links, sets options, prints number" {
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/create" \
    run "$SCRIPTS/board-create.sh" acme widget "widget"
  [ "$status" -eq 0 ]
  [ "$output" = "7" ]
  grep -q "project create --owner acme --title widget --format json" "$GH_LOG"
  grep -q "project link 7 --owner acme --repo widget" "$GH_LOG"
  [ "$(grep -c "api graphql" "$GH_LOG")" -eq 2 ]
}
