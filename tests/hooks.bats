#!/usr/bin/env bats

setup() {
  HOOKS="$BATS_TEST_DIRNAME/../plugin/hooks"
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

@test "session-start: conveyor repo with matching stamp → no nudge" {
  t="$(mktemp -d)"; mkdir -p "$t/.claude"
  v="$(jq -r .version "$BATS_TEST_DIRNAME/../plugin/.claude-plugin/plugin.json")"
  printf '{"pluginVersion":"%s"}' "$v" > "$t/.claude/conveyor.json"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  rm -rf "$t"
  [[ "$ctx" == *"working principles"* ]]
  [[ "$ctx" != *"run /conveyor:doctor to reconcile"* ]]
}

@test "session-start: stale or missing stamp → nudge with versions" {
  t="$(mktemp -d)"; mkdir -p "$t/.claude"
  printf '{"pluginVersion":"0.0.1"}' > "$t/.claude/conveyor.json"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"conveyor plugin updated 0.0.1 → "* ]]
  [[ "$ctx" == *"run /conveyor:doctor to reconcile."* ]]
  printf '{}' > "$t/.claude/conveyor.json"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  rm -rf "$t"
  [[ "$ctx" == *"conveyor plugin updated unstamped → "* ]]
}

@test "session-start: no conveyor.json → no nudge" {
  t="$(mktemp -d)"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  rm -rf "$t"
  [[ "$ctx" == *"working principles"* ]]
  [[ "$ctx" != *"reconcile"* ]]
}
