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
  # id-preserving rename: the mapped/kept options carry their original option id
  [ "$(jq -r '.variables.opts[] | select(.name=="Backlog") | .id' "$TMP/last-graphql.json")" = "opt_td" ]
  [ "$(jq -r '.variables.opts[] | select(.name=="In Progress") | .id' "$TMP/last-graphql.json")" = "opt_ip" ]
  [ "$(jq -r '.variables.opts[] | select(.name=="Done") | .id' "$TMP/last-graphql.json")" = "opt_dn" ]
  # appended canonicals carry NO id (GitHub creates them fresh)
  [ "$(jq -r '.variables.opts[] | select(.name=="QA") | has("id")' "$TMP/last-graphql.json")" = "false" ]
  [ "$(jq -r '[.variables.opts[] | select(has("id") | not)] | length' "$TMP/last-graphql.json")" -eq 5 ]
}

@test "reconcile keeps a non-mapped, non-canonical option verbatim" {
  echo '{"backlog":"Todo","inProgress":"In Progress","done":"Done"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile-icebox" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.variables.opts[] | select(.name=="Icebox")] | length' "$TMP/last-graphql.json")" -eq 1 ]
  # Icebox kept its id too
  [ "$(jq -r '.variables.opts[] | select(.name=="Icebox") | .id' "$TMP/last-graphql.json")" = "opt_ib" ]
  # 4 existing (Todo→Backlog, In Progress, Done, Icebox) + 5 appended
  [ "$(jq -r '.variables.opts | length' "$TMP/last-graphql.json")" -eq 9 ]
}

@test "reconcile creates the Priority field when the board has none" {
  echo '{"backlog":"Todo","inProgress":"In Progress","done":"Done"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile-noprio" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -eq 0 ]
  # CreatePriorityField is the last mutation, so last-graphql.json holds its payload
  [ "$(jq -r '.query | contains("CreatePriorityField")' "$TMP/last-graphql.json")" = "true" ]
  for p in P1 P2 P3; do
    run jq -e --arg n "$p" '.variables.opts[] | select(.name==$n)' "$TMP/last-graphql.json"
    [ "$status" -eq 0 ]
  done
}

@test "reconcile rejects a mapping value that is not an existing option name" {
  echo '{"backlog":"Nonexistent Column"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not an existing option name"* && "$output" == *"Nonexistent Column"* ]]
}

@test "reconcile rejects a rename target that collides with an existing option name" {
  echo '{"done":"Finished"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile-dup" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate option name"* ]]
}

@test "reconcile rejects a mapping whose values repeat" {
  echo '{"done":"Done","qa":"Done"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate mapping value"* ]]
}

@test "reconcile rejects an unknown canonical key" {
  echo '{"notAState":"Todo"}' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown canonical key"* && "$output" == *"notAState"* ]]
}

@test "reconcile rejects a 0-byte mapping file" {
  : > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a JSON object"* ]]
}

@test "reconcile rejects a non-object (array) mapping file" {
  echo '["backlog","Todo"]' > "$TMP/map.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/reconcile" \
    run "$SCRIPTS/board-reconcile.sh" acme 7 "$TMP/map.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a JSON object"* ]]
}

@test "reconcile prints usage on wrong argument count" {
  run "$SCRIPTS/board-reconcile.sh" acme 7
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: board-reconcile.sh OWNER PROJECT_NUMBER MAPPING_JSON_FILE"* ]]
}
