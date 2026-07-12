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
  grep -qF 'mode=background' <<<"$output"
  wait_sentinel "$TMP/r1.md.done"
  [ -f "$TMP/r1.md" ]
  [ "$(cat "$TMP/r1.md.done")" = "0" ]
  [ "$(grep -c '^session id: ' "$TMP/r1.log")" = "1" ]
  run bash -c "LC_ALL=C grep -q \$'\x1b' '$TMP/r1.log'"
  [ "$status" -ne 0 ]
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
  [[ "$output" == *"-s read-only"* && "$output" == *"-m gpt-5.6-sol"* && "$output" == *"-o $TMP/r1.md"* && "$output" == *"--json"* ]]
}

@test "run tmux mode: pane spawned with runner script" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  grep -qF 'mode=tmux' <<<"$output"
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-d -h -l 40%' <<<"$output"
  grep -qF "$TMP/r1.run.sh" <<<"$output"
  run grep -F 'tmux select-pane' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-T codex-gpt-5.6-sol' <<<"$output"
  # pane never ran (tmux is mocked) — assert the runner's contract instead;
  # don't execute it: the appended 'sleep 10' linger would stall the suite
  run cat "$TMP/r1.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex exec"* && "$output" == *"> $TMP/r1.md.done"* && "$output" == *"sleep 10"* && "$output" == *"--json"* && "$output" == *"codex-exec.sh render $TMP/r1.log"* && "$output" == *"printf -- '--------------"* ]]
}

@test "run iterm mode: split vertically, session named after agent" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility iterm"
  [ "$status" -eq 0 ]
  run grep -F 'osascript' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'iTerm2'* && "$output" == *'split vertically'* && "$output" == *'set name of newSession to "codex-gpt-5.6-sol"'* ]]
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

@test "run resume: read-only via -c sandbox_mode, never -s or --last; report created" {
  use_cfg
  printf 'rebuttal\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/r2.md.done"
  [ -f "$TMP/r2.md" ]
  [ "$(cat "$TMP/r2.md.done")" = "0" ]
  run cat "$TMP/r2.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'codex exec resume 0000-mock-session'* && "$output" == *'sandbox_mode="read-only"'* && "$output" != *'-s read-only'* && "$output" != *'--last'* && "$output" == *"--json"* ]]
}

@test "run without required args → usage" {
  use_cfg
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name x"
  [ "$status" -eq 2 ]
}

@test "session-id dies when log has no session id header" {
  printf -- '--------\nno header here\n--------\n' > "$TMP/r1.log"
  run bash -c "'$SCRIPTS/codex-exec.sh' session-id '$TMP/r1.log'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no session id"* ]]
}

@test "run --sandbox workspace-write: fresh uses -s workspace-write" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol--55-1 --model gpt-5.6-sol --out '$TMP/w1.md' --prompt-file '$TMP/p.txt' --sandbox workspace-write"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w1.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s workspace-write"* ]]
}

@test "run --sandbox workspace-write resume: -c sandbox_mode, never -s" {
  use_cfg
  printf 'fix\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol--55-1 --model gpt-5.6-sol --out '$TMP/w2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session --sandbox workspace-write"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w2.md.done"
  run cat "$TMP/w2.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'sandbox_mode="workspace-write"'* && "$output" != *'-s workspace-write'* ]]
}

@test "run --sandbox bogus value → usage" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/x.md' --prompt-file '$TMP/p.txt' --sandbox sometimes"
  [ "$status" -eq 2 ]
}

@test "run --workdir: runner cds there before codex" {
  use_cfg
  mkdir "$TMP/wt"
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w3.md' --prompt-file '$TMP/p.txt' --workdir '$TMP/wt'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w3.md.done"
  run cat "$TMP/w3.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cd $TMP/wt"* ]]
}

@test "run --workdir missing dir → dies at spawn" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w4.md' --prompt-file '$TMP/p.txt' --workdir '$TMP/nope'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no workdir"* ]]
}

@test "run --workdir with relative --out → dies" {
  use_cfg
  mkdir "$TMP/wt"
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out rel.md --prompt-file '$TMP/p.txt' --workdir '$TMP/wt'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute --out/--prompt-file required with --workdir"* ]]
}

@test "run default sandbox unchanged: read-only" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w5.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/w5.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s read-only"* ]]
}

@test "render: raw JSONL kept, one synthetic session line, no ESC, survives garbage" {
  printf '%s\n' \
    '{"type":"thread.started","thread_id":"0000-mock-session"}' \
    'garbage not json' \
    '{"type":"unknown.event","x":1}' \
    '{"type":"turn.completed","usage":{"input_tokens":5,"output_tokens":2}}' \
    > "$TMP/ev.jsonl"
  run bash -c "'$SCRIPTS/codex-exec.sh' render '$TMP/o.log' '$TMP/o.md' < '$TMP/ev.jsonl'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^session id: ' "$TMP/o.log")" = "1" ]
  [ "$(grep -cF 'garbage not json' "$TMP/o.log")" = "1" ]
  run bash -c "LC_ALL=C grep -q \$'\x1b' '$TMP/o.log'"
  [ "$status" -ne 0 ]
}

@test "render: command shown once, output hidden, failure marked red-path" {
  printf '%s\n' \
    '{"type":"item.started","item":{"id":"i0","type":"command_execution","command":"echo hi","status":"in_progress"}}' \
    '{"type":"item.completed","item":{"id":"i0","type":"command_execution","command":"echo hi","aggregated_output":"SECRET_OUTPUT","exit_code":0,"status":"completed"}}' \
    '{"type":"item.started","item":{"id":"i1","type":"command_execution","command":"false","status":"in_progress"}}' \
    '{"type":"item.completed","item":{"id":"i1","type":"command_execution","command":"false","aggregated_output":"","exit_code":1,"status":"completed"}}' \
    > "$TMP/ev.jsonl"
  run bash -c "'$SCRIPTS/codex-exec.sh' render '$TMP/o.log' '$TMP/o.md' < '$TMP/ev.jsonl'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'$ echo hi'* && "$output" != *SECRET_OUTPUT* && "$output" == *'exit 1: false'* ]]
}

@test "render: file change as kind + cwd-relative path" {
  printf '%s\n' \
    "{\"type\":\"item.completed\",\"item\":{\"id\":\"i2\",\"type\":\"file_change\",\"changes\":[{\"path\":\"$TMP/CHANGES.md\",\"kind\":\"add\"}],\"status\":\"completed\"}}" \
    > "$TMP/ev.jsonl"
  run bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' render '$TMP/o.log' '$TMP/o.md' < '$TMP/ev.jsonl'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'add CHANGES.md'* && "$output" != *"add $TMP/CHANGES.md"* ]]
}

@test "render: full agent message, report path once at end" {
  printf '%s\n' \
    '{"type":"item.completed","item":{"id":"i3","type":"agent_message","text":"first msg"}}' \
    '{"type":"item.completed","item":{"id":"i4","type":"agent_message","text":"final msg with a very long body that must not be truncated"}}' \
    > "$TMP/ev.jsonl"
  run bash -c "'$SCRIPTS/codex-exec.sh' render '$TMP/o.log' '$TMP/o.md' < '$TMP/ev.jsonl'"
  [ "$status" -eq 0 ]
  [ "$(grep -cF "report: $TMP/o.md" <<<"$output")" = "1" ]
  [[ "$output" == *'first msg'* && "$output" == *'must not be truncated'* ]]
}

@test "run: failing codex → sentinel nonzero, garbage logged, renderer survives" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_FAIL=3 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/f1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/f1.md.done"
  [ "$(cat "$TMP/f1.md.done")" = "3" ]
  run grep -cF 'Not inside a trusted directory' "$TMP/f1.log"
  [[ "$output" == "1" ]]
}
