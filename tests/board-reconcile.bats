#!/usr/bin/env bats
load helpers/env

@test "reconcile preserves existing, renames mapped, appends missing" {
  echo '{"backlog":"Todo","inProgress":"In Progress","done":"Done"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -eq 0 ]
  for name in "Human Only" "Backlog" "Ready for dev" "In Progress" "Agent Review" "QA" "Done" "Archived"; do
    run jq -e --arg n "$name" '.variables.opts[] | select(.name==$n)' "$TMP/last-graphql.json"
    [ "$status" -eq 0 ]
  done
  # Todo was renamed to Backlog — gone from the payload
  run jq -e '.variables.opts[] | select(.name=="Todo")' "$TMP/last-graphql.json"
  [ "$status" -ne 0 ]
  # mapped existing options preserved exactly once each
  [ "$(jq -r '[.variables.opts[] | select(.name=="In Progress")] | length' "$TMP/last-graphql.json")" -eq 1 ]
  [ "$(jq -r '[.variables.opts[] | select(.name=="Done")] | length' "$TMP/last-graphql.json")" -eq 1 ]
  # 3 existing (renamed/kept) + 5 appended, no strays
  [ "$(jq -r '.variables.opts | length' "$TMP/last-graphql.json")" -eq 8 ]
}

@test "reconcile keeps a non-mapped, non-canonical option verbatim" {
  echo '{"backlog":"Todo","inProgress":"In Progress","done":"Done"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile-icebox" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.variables.opts[] | select(.name=="Icebox")] | length' "$TMP/last-graphql.json")" -eq 1 ]
  # 4 existing (Todo→Backlog, In Progress, Done, Icebox) + 5 appended
  [ "$(jq -r '.variables.opts | length' "$TMP/last-graphql.json")" -eq 9 ]
}
