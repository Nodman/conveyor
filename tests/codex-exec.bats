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

wait_sentinel() { # $1=path — poll up to ~5s
  for _ in $(seq 1 50); do [ -f "$1" ] && return 0; sleep 0.1; done
  return 1
}

@test "run background: sentinel, report, log with session id" {
  use_cfg
  printf 'the question\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=background"* ]]
  wait_sentinel "$TMP/r1.md.done"
  [ -f "$TMP/r1.md" ]
  run bash -c "'$SCRIPTS/codex-exec.sh' session-id '$TMP/r1.log'"
  [ "$output" = "0000-mock-session" ]
}

@test "run codex args: read-only, model, stdin prompt" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/r1.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s read-only"* && "$output" == *"-m gpt-5.6-sol"* && "$output" == *"-o $TMP/r1.md"* ]]
}

@test "run tmux mode: pane spawned with runner script" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mode=tmux"* ]]
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TMP/r1.run.sh"* ]]
  # pane never ran (tmux is mocked) — assert the runner's contract instead;
  # don't execute it: the appended 'sleep 10' linger would stall the suite
  run cat "$TMP/r1.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* && "$output" == *"touch $TMP/r1.md.done"* && "$output" == *"sleep 10"* ]]
}

@test "run window mode: osascript Terminal spawn" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility window"
  [ "$status" -eq 0 ]
  run grep -F 'osascript' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Terminal"* && "$output" == *"$TMP/r1.run.sh"* ]]
}

@test "run resume: explicit session id, never --last" {
  use_cfg
  printf 'rebuttal\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session"
  wait_sentinel "$TMP/r2.md.done"
  run grep -F 'codex exec resume' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0000-mock-session"* && "$output" != *"--last"* ]]
}

@test "run without required args → usage" {
  use_cfg
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name x"
  [ "$status" -eq 2 ]
}
