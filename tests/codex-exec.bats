#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }
# every invocation scrubs terminal vars so the dev's real tmux/iTerm doesn't leak in
CX="env -u TMUX -u TMUX_PANE LC_TERMINAL= TERM_PROGRAM="

run_pty() {
  local command="${1:?}"
  if script --version >/dev/null 2>&1; then
    run script -qec "$command" /dev/null
  else
    run script -q /dev/null bash -c "$command"
  fi
}

@test "run_pty: util-linux syntax propagates command status" {
  script() {
    if [ "${1:-}" = "--version" ]; then return 0; fi
    [ "$#" -eq 3 ] || return 91
    [ "$1" = "-qec" ] || return 92
    [ "$3" = "/dev/null" ] || return 93
    bash -c "$2"
  }
  run_pty "printf portable"
  [ "$status" -eq 0 ]
  [ "$output" = "portable" ]
  run_pty "exit 7"
  [ "$status" -eq 7 ]
}

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

@test "run background: .job record has pid, mode, paths" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/j1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  [ -f "$TMP/j1.job" ]
  run jq -r .mode "$TMP/j1.job"
  [ "$output" = "background" ]
  run jq -e '.pid > 0' "$TMP/j1.job"
  [ "$status" -eq 0 ]
  run jq -r .sentinel "$TMP/j1.job"
  [ "$output" = "$TMP/j1.md.done" ]
  grep -qF "job=$TMP/j2.job" <<<"$(cd "$TMP" && $CX "$SCRIPTS/codex-exec.sh" run --name n --model m --out "$TMP/j2.md" --prompt-file "$TMP/p.txt")"
}

@test "kill: background run TERMs codex, worker writes 143 sentinel" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_SLOW=60 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/k1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  sleep 1
  run bash -c "'$SCRIPTS/codex-exec.sh' kill '$TMP/k1.md'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/k1.md.done"
  code="$(cat "$TMP/k1.md.done")"
  [ "$code" != "0" ]
}

@test "kill: finished run → already done, sentinel untouched" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/k2.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/k2.md.done"
  run bash -c "'$SCRIPTS/codex-exec.sh' kill '$TMP/k2.md'"
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/k2.md.done")" = "0" ]
  [[ "$output" == *"already done"* ]]
}

@test "kill: no .job record → dies" {
  run bash -c "'$SCRIPTS/codex-exec.sh' kill '$TMP/nope.md'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no job record"* ]]
}

@test "run codex args: default full-access, model, stdin prompt" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/r1.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s danger-full-access"* && "$output" == *"-m gpt-5.6-sol"* && "$output" == *"-c tools.web_search=true"* && "$output" == *"-o $TMP/r1.md"* && "$output" == *"--json"* ]]
}

@test "run: generated runner announces name, sandbox, and model first" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol--82-1 --model gpt-5.6-sol --out '$TMP/a1.md' --prompt-file '$TMP/p.txt' --sandbox workspace-write --visibility window"
  [ "$status" -eq 0 ]
  run "$TMP/a1.run.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'Spawning [codex-gpt-5.6-sol--82-1 sandbox=workspace-write model=gpt-5.6-sol]' ]
}

@test "run: spawn announcement includes workdir when set" {
  use_cfg
  mkdir "$TMP/wt"
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name agent-82 --model model-82 --out '$TMP/a2.md' --prompt-file '$TMP/p.txt' --workdir '$TMP/wt' --visibility window"
  [ "$status" -eq 0 ]
  run "$TMP/a2.run.sh"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Spawning [agent-82 sandbox=danger-full-access model=model-82 workdir=$TMP/wt]" ]
}

@test "run: spawn metadata color is deterministic and excludes reserved colors" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name agent-alpha --model m --out '$TMP/c1.md' --prompt-file '$TMP/p.txt' --visibility window"
  [ "$status" -eq 0 ]
  color1="$(sed -n 's/^spawn=agent-alpha sandbox=danger-full-access color=//p' <<<"$output")"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name agent-alpha --model m --out '$TMP/c2.md' --prompt-file '$TMP/p.txt' --visibility window"
  [ "$status" -eq 0 ]
  color2="$(sed -n 's/^spawn=agent-alpha sandbox=danger-full-access color=//p' <<<"$output")"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name agent-beta --model m --out '$TMP/c3.md' --prompt-file '$TMP/p.txt' --visibility window"
  [ "$status" -eq 0 ]
  color3="$(sed -n 's/^spawn=agent-beta sandbox=danger-full-access color=//p' <<<"$output")"
  case "$color1:$color2:$color3" in
    34:34:33|34:34:35|34:34:36|35:35:34|35:35:33|35:35:36|33:33:34|33:33:35|33:33:36|36:36:34|36:36:35|36:36:33) true ;;
    *) false ;;
  esac
}

@test "run: spawn announcement uses the agent color on a tty and stays out of log" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name agent-alpha --model m --out '$TMP/t1.md' --prompt-file '$TMP/p.txt' --visibility window"
  [ "$status" -eq 0 ]
  color="$(sed -n 's/^spawn=agent-alpha sandbox=danger-full-access color=//p' <<<"$output")"
  [ "$(grep -cF "codex-exec.sh render $TMP/t1.log $TMP/t1.md $color" "$TMP/t1.run.sh")" -eq 1 ]
  run_pty "'$TMP/t1.run.sh'"
  [ "$status" -eq 0 ]
  tty_output="$output"
  expected="$(printf '\033[%smSpawning [agent-alpha sandbox=danger-full-access model=m]\033[0m' "$color")"
  run bash -c "LC_ALL=C grep -q \$'\x1b' '$TMP/t1.log'"
  [ "$status" -ne 0 ]
  [ "$tty_output" != "${tty_output#*"$expected"}" ]
}

@test "run tmux mode: no right split creates targeted horizontal split" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX TMUX_PANE=%1 MOCK_TMUX_LAYOUT=no-split '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  grep -qF 'mode=tmux' <<<"$output"
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-d -h -l 40% -t %1' <<<"$output"
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

@test "run tmux mode: .job record has pane id" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX TMUX_PANE=%1 MOCK_TMUX_LAYOUT=no-split '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/j3.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  run jq -r .pane "$TMP/j3.job"
  [ "$output" = "%99" ]
}

@test "run tmux mode: existing right split stacks under bottom-most pane" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX TMUX_PANE=%1 MOCK_TMUX_LAYOUT=split-exists '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-d -v -t %3' <<<"$output"
}

@test "run tmux mode: session pane target propagates through tmux calls" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX TMUX_PANE=%session MOCK_TMUX_LAYOUT=no-split '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  grep -qF 'tmux display-message -p -t %session #{window_id}' "$RUN_LOG"
  grep -qF 'tmux list-panes -t @7 -F #{pane_id} #{pane_at_right}' "$RUN_LOG"
  grep -qF 'tmux split-window -d -h -l 40% -t %session' "$RUN_LOG"
  grep -qF 'tmux select-pane -t %99 -T codex-gpt-5.6-sol' "$RUN_LOG"
}

@test "run tmux mode: unset session pane preserves current-window fallback" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-d -h -l 40% -P -F #{pane_id}' <<<"$output"
  run grep -qF 'tmux display-message' "$RUN_LOG"
  [ "$status" -ne 0 ]
  run grep -qF 'tmux list-panes' "$RUN_LOG"
  [ "$status" -ne 0 ]
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

@test "run resume: default sandbox via -c sandbox_mode, never -s or --last; report created" {
  use_cfg
  printf 'rebuttal\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/r2.md.done"
  [ -f "$TMP/r2.md" ]
  [ "$(cat "$TMP/r2.md.done")" = "0" ]
  run cat "$TMP/r2.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'codex exec resume 0000-mock-session'* && "$output" == *'sandbox_mode="danger-full-access"'* && "$output" != *'-s danger-full-access'* && "$output" != *'--last'* && "$output" == *"-c tools.web_search=true"* && "$output" == *"--json"* ]]
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

@test "run default sandbox: danger-full-access (yolo ruling)" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w5.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/w5.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s danger-full-access"* ]]
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

@test "render: missing color argument defaults main output to cyan on a tty" {
  printf '%s\n' \
    '{"type":"item.completed","item":{"type":"agent_message","text":"default color"}}' \
    > "$TMP/default-color.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/default-color.log' < '$TMP/default-color.jsonl'"
  [ "$status" -eq 0 ]
  expected="$(printf '\033[36mdefault color\033[0m')"
  [ "$output" != "${output#*"$expected"}" ]
}

@test "render: third argument sets command and agent-message color on a tty" {
  printf '%s\n' \
    '{"type":"item.started","item":{"type":"command_execution","command":"echo hi"}}' \
    '{"type":"item.completed","item":{"type":"agent_message","text":"custom color"}}' \
    > "$TMP/custom-color.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/custom-color.log' '' 35 < '$TMP/custom-color.jsonl'"
  [ "$status" -eq 0 ]
  command_expected="$(printf '\033[35m$ echo hi \033[0m')"
  message_expected="$(printf '\033[35mcustom color\033[0m')"
  [ "$output" != "${output#*"$command_expected"}" ]
  [ "$output" != "${output#*"$message_expected"}" ]
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

@test "run: codex exit 0 but no report → sentinel 97, reason in log" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_NO_REPORT=1 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/v1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/v1.md.done"
  [ "$(cat "$TMP/v1.md.done")" = "97" ]
  run grep -c 'no report' "$TMP/v1.log"
  [ "$output" = "1" ]
}

@test "run --output-schema: non-JSON report → sentinel 98" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_BAD_REPORT=1 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/v2.md' --prompt-file '$TMP/p.txt' --output-schema '$SCRIPTS/../config/report.schema.json'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/v2.md.done"
  [ "$(cat "$TMP/v2.md.done")" = "98" ]
}

@test "run --output-schema: valid JSON report → sentinel 0" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/v3.md' --prompt-file '$TMP/p.txt' --output-schema '$SCRIPTS/../config/report.schema.json'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/v3.md.done"
  [ "$(cat "$TMP/v3.md.done")" = "0" ]
}

@test "run --output-schema passthrough: fresh and resume" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s1.md' --prompt-file '$TMP/p.txt' --output-schema '$SCRIPTS/../config/report.schema.json'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/s1.md.done"
  grep -q -- '--output-schema' "$TMP/s1.run.sh"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session --output-schema '$SCRIPTS/../config/report.schema.json'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/s2.md.done"
  grep -q -- '--output-schema' "$TMP/s2.run.sh"
}

@test "run --sandbox danger-full-access: fresh -s, resume -c sandbox_mode" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/d1.md' --prompt-file '$TMP/p.txt' --sandbox danger-full-access"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/d1.md.done"
  grep -qF -- '-s danger-full-access' "$TMP/d1.run.sh"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/d2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session --sandbox danger-full-access"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/d2.md.done"
  grep -qF 'sandbox_mode="danger-full-access"' "$TMP/d2.run.sh"
  ! grep -qF -- '-s danger-full-access' "$TMP/d2.run.sh"
}

@test "audit extracts privileged commands only" {
  use_cfg
  run bash -c "'$SCRIPTS/codex-exec.sh' audit '$BATS_TEST_DIRNAME/fixtures/codex-escalated.log'"
  [ "$status" -eq 0 ]
  grep -qF 'gh api' <<<"$output"
  grep -qF 'git push' <<<"$output"
  grep -qF 'core.hooksPath=/dev/null commit' <<<"$output"
  ! grep -qF 'ls -la' <<<"$output"
}

@test "report schema: six required fields, every property described" {
  local schema="$SCRIPTS/../config/report.schema.json"
  run jq -e '.required == ["verdict","message","privileged_actions","denials","commit_shas","tests"]' "$schema"
  [ "$status" -eq 0 ]
  run jq -e '[.properties[] | .description // ""] | all(length > 0)' "$schema"
  [ "$status" -eq 0 ]
  run jq -e '.properties.message.type == "string"' "$schema"
  [ "$status" -eq 0 ]
}

@test "render: schema report pretty-printed, default FG, none for empty arrays" {
  local rpt='{"verdict":"comment","message":"Plan holds; two nits.","privileged_actions":[{"command":"gh pr view 12","exit_code":0}],"denials":[],"commit_shas":[],"tests":["bats tests/ — pass"]}'
  jq -nc --arg t "$rpt" '{"type":"item.completed","item":{"type":"agent_message","text":$t}}' > "$TMP/rp.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/rp.log' '' 35 < '$TMP/rp.jsonl'"
  [ "$status" -eq 0 ]
  grep -qF 'Plan holds; two nits.' <<<"$output"
  grep -qF 'verdict: comment' <<<"$output"
  grep -qF 'tests: bats tests/ — pass' <<<"$output"
  grep -qF 'privileged: gh pr view 12 (exit 0)' <<<"$output"
  grep -qF 'commits: none' <<<"$output"
  grep -qF 'denials: none' <<<"$output"
  colored="$(printf '\033[35mPlan holds')"
  [ "$output" = "${output#*"$colored"}" ]   # message NOT in agent color
  ! grep -qF '"verdict"' <<<"$output"        # raw JSON not shown
}

@test "render: JSON without verdict falls back to raw agent-color path" {
  jq -nc '{"type":"item.completed","item":{"type":"agent_message","text":"{\"note\":\"just json\"}"}}' > "$TMP/rf.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/rf.log' '' 35 < '$TMP/rf.jsonl'"
  [ "$status" -eq 0 ]
  raw_expected="$(printf '\033[35m{"note":"just json"}\033[0m')"
  [ "$output" != "${output#*"$raw_expected"}" ]
}

@test "render: report fallback is atomic when pretty-print fails" {
  local rpt='{"verdict":"comment","message":"No partial block.","privileged_actions":[],"denials":[],"commit_shas":[],"tests":"not-an-array"}'
  jq -nc --arg t "$rpt" '{"type":"item.completed","item":{"type":"agent_message","text":$t}}' > "$TMP/ra.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/ra.log' '' 35 < '$TMP/ra.jsonl'"
  [ "$status" -eq 0 ]
  raw_expected="$(printf '\033[35m%s\033[0m' "$rpt")"
  [ "$output" != "${output#*"$raw_expected"}" ]
  ! grep -qF 'verdict: comment' <<<"$output"
}

@test "run resume: passes -m <model> (spec: escalation must not silently no-op)" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model gpt-5.6-sol --out '$TMP/m1.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/m1.md.done"
  [ "$(cat "$TMP/m1.md.done")" = "0" ]
  run cat "$TMP/m1.run.sh"
  [[ "$output" == *'codex exec resume 0000-mock-session -m gpt-5.6-sol'* ]]
}

@test "run --effort: -c model_reasoning_effort on fresh and resume" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/e1.md' --prompt-file '$TMP/p.txt' --effort high"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/e1.md.done"
  [ "$(cat "$TMP/e1.md.done")" = "0" ]
  grep -qF -- '-c model_reasoning_effort=high' "$TMP/e1.run.sh"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/e2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session --effort low"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/e2.md.done"
  grep -qF -- '-c model_reasoning_effort=low' "$TMP/e2.run.sh"
}

@test "run without --effort: model_reasoning_effort never passed" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/e3.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/e3.md.done"
  run grep -F 'model_reasoning_effort' "$TMP/e3.run.sh"
  [ "$status" -ne 0 ]
}

@test "run --effort bogus value → usage" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/e4.md' --prompt-file '$TMP/p.txt' --effort turbo"
  [ "$status" -eq 2 ]
}
