#!/usr/bin/env bats
load helpers/env

@test "plugin manifest is valid JSON with required fields" {
  run jq -er '.name, .version, .description' "$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json"
  [ "$status" -eq 0 ]
}

@test "gh stub replays a fixture and logs the call" {
  mkdir -p "$TMP/fix"
  echo '{"ok":true}' > "$TMP/fix/project_view.out"
  GH_FIX="$TMP/fix" run gh project view 7 --owner acme
  [ "$status" -eq 0 ]
  [ "$output" = '{"ok":true}' ]
  grep -q "project view 7 --owner acme" "$GH_LOG"
}

@test "gh stub matches graphql fixtures by operation name from stdin" {
  mkdir -p "$TMP/fix"
  echo '{"data":{}}' > "$TMP/fix/graphql_UpdateStatusOptions.out"
  GH_FIX="$TMP/fix" run bash -c 'echo "{\"query\":\"mutation UpdateStatusOptions(...)\"}" | gh api graphql --input -'
  [ "$status" -eq 0 ]
  [ "$output" = '{"data":{}}' ]
}

@test "gh stub fails loudly on missing fixture" {
  GH_FIX="$TMP" run gh nonexistent thing
  [ "$status" -eq 64 ]
}
