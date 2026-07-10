#!/usr/bin/env bats

setup() {
  HOOKS="$BATS_TEST_DIRNAME/../hooks"
}

@test "session-start: subagent stdin → exactly {}" {
  run bash -c "printf '%s' '{\"agent_type\":\"general-purpose\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "session-start: normal stdin → valid JSON with context" {
  run bash -c "printf '%s' '{\"session_id\":\"x\",\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . >/dev/null
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"working principles"* ]]
  [[ "$ctx" == *"/conveyor:work"* ]]
}

@test "session-start: malformed stdin → exit 0, still emits context" {
  run bash -c "printf 'not json' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"working principles"* ]]
}

@test "guard-docs: CLAUDE.md path → reminder" {
  run bash -c "printf '%s' '{\"tool_input\":{\"file_path\":\"foo/CLAUDE.md\"}}' | '$HOOKS/guard-docs.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"durable rules"* ]]
}

@test "guard-docs: AGENTS.md path → reminder" {
  run bash -c "printf '%s' '{\"tool_input\":{\"file_path\":\"AGENTS.md\"}}' | '$HOOKS/guard-docs.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"durable rules"* ]]
}

@test "guard-docs: non-doc path → empty output, exit 0" {
  run bash -c "printf '%s' '{\"tool_input\":{\"file_path\":\"src/main.swift\"}}' | '$HOOKS/guard-docs.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard-docs: malformed stdin → exit 0, empty output" {
  run bash -c "printf 'not json' | '$HOOKS/guard-docs.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
