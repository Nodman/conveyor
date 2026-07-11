#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }
# every invocation scrubs terminal vars so the dev's real tmux/iTerm doesn't leak in
CX="env -u TMUX LC_TERMINAL= TERM_PROGRAM="

@test "detect: TMUX set wins" {
  use_cfg
  run bash -c "cd '$TMP' && env TMUX=/tmp/sock LC_TERMINAL= TERM_PROGRAM= '$SCRIPTS/codex-exec.sh' detect"
  [ "$status" -eq 0 ]
  [ "$output" = "tmux" ]
}

@test "detect: iTerm2 via TERM_PROGRAM when no tmux" {
  use_cfg
  run bash -c "cd '$TMP' && env -u TMUX LC_TERMINAL= TERM_PROGRAM=iTerm.app '$SCRIPTS/codex-exec.sh' detect"
  [ "$status" -eq 0 ]
  [ "$output" = "iterm" ]
}

@test "detect: falls back to config preference" {
  use_cfg
  jq '.externalAgents.fallbackVisibility = "window"' "$TMP/.claude/conveyor.json" > "$TMP/c.json"
  mv "$TMP/c.json" "$TMP/.claude/conveyor.json"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' detect"
  [ "$status" -eq 0 ]
  [ "$output" = "window" ]
}

@test "detect: unset when no terminal and no preference" {
  use_cfg
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' detect"
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "set-visibility writes the config key" {
  use_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' set-visibility background"
  [ "$status" -eq 0 ]
  run jq -r '.externalAgents.fallbackVisibility' "$TMP/.claude/conveyor.json"
  [ "$output" = "background" ]
}

@test "set-visibility rejects bogus value" {
  use_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' set-visibility sometimes"
  [ "$status" -eq 2 ]
}

@test "preflight ok with mock codex" {
  use_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' preflight"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "session-id extracts uuid from log" {
  printf -- '--------\nsession id: 019f-abc\n--------\n' > "$TMP/r1.log"
  run bash -c "'$SCRIPTS/codex-exec.sh' session-id '$TMP/r1.log'"
  [ "$status" -eq 0 ]
  [ "$output" = "019f-abc" ]
}
