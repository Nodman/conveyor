# Plan: codex pane placement, title, condensed JSONL renderer

Spec: `docs/specs/2026-07-12-codex-pane-renderer.md` (approved 2026-07-12).

**Goal:** codex agent panes open to the right (40%), titled with the agent
name, showing a condensed colored activity feed instead of the raw stream, in
tmux and iTerm, without touching the `session_id()`/sentinel/`-o` contracts.

**Architecture:** `codex exec` gains `--json` in both command shapes; the
runner pipes the JSONL through a new `render` subcommand in the same script.
`render` appends every raw line to the log (plus one synthetic plain
`session id:` line), and prints one short colored line per event to stdout.
Color only when stdout is a TTY, so background logs stay byte-clean.

**Global constraints (from spec):**
- render path runs with `set +e`; a malformed event must never kill the pipe
- raw line goes to the log BEFORE any parsing
- log: exactly one `^session id: ` line, zero ESC bytes
- sentinel carries codex's exit code via `PIPESTATUS[0]` — unchanged
- no resume seeding — resume re-emits `thread.started` with the same id
- blank line after every rendered entry
- bats gotcha: only the LAST assertion gates — decisive `[[ ]]` last, `[ ]` mid-test
- codex gotcha: mocks reject what the real CLI rejects; live-verify each new arg shape once

## File map

| file | responsibility |
|---|---|
| `plugin/scripts/codex-exec.sh` | `render` subcommand; runner gains `--json`, prompt echo, render pipe; tmux `-h -l 40%` + title; iTerm split vertically + session name |
| `tests/helpers/bin/codex` | mock: JSONL branch under `--json`; reject resume+`--color`; `MOCK_CODEX_FAIL` failure branch |
| `tests/codex-exec.bats` | 4 new render unit tests, 2 new run tests (iterm, failing codex), update 4 existing run assertions |
| `plugin/.claude-plugin/plugin.json` | version 0.1.19 → 0.1.20 |

Single PR. No other files.

## Task 1 — `render` subcommand + unit tests

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Produces: `codex-exec.sh render <log> <report-path>` — reads the codex
`--json` stream on stdin. Consumed by task 3's runner.

- [ ] Write failing tests (append to `tests/codex-exec.bats`):

```bats
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
```

- [ ] Run `npx bats tests/codex-exec.bats` (per running-tests skill) — the 4
      new tests fail (`render` is unknown → usage, exit 2).
- [ ] Implement in `plugin/scripts/codex-exec.sh`. Add to `usage()`:
      `echo "       codex-exec.sh render <log> <report> (internal: codex --json stream on stdin)"`.
      Add the function (after `session_id()`):

```bash
render_stream() {
  set +e   # a display bug must never SIGPIPE-kill the codex run
  local log="${1:?}" report="${2:-}"
  local B="" R="" G="" C="" D="" N=""
  if [[ -t 1 ]]; then
    B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
  fi
  : > "$log"
  local line type itype txt cmd rc
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$log"
    if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
      printf '%s! %s%s\n\n' "$D" "$line" "$N"
      continue
    fi
    type=$(jq -r '.type // empty' <<<"$line" 2>/dev/null)
    case "$type" in
      thread.started)
        txt=$(jq -r '.thread_id // empty' <<<"$line" 2>/dev/null)
        if [[ -n "$txt" ]]; then
          printf 'session id: %s\n' "$txt" >> "$log"
          printf '%ssession %s%s\n\n' "$B" "$txt" "$N"
        fi ;;
      item.started|item.completed)
        itype=$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)
        case "$itype" in
          command_execution)
            cmd=$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-120)
            if [[ "$type" == item.started && -n "$cmd" ]]; then
              printf '%s$ %s%s\n\n' "$C" "$cmd" "$N"
            elif [[ "$type" == item.completed ]]; then
              rc=$(jq -r '.item.exit_code // 0' <<<"$line" 2>/dev/null)
              if [[ "$rc" != 0 ]]; then printf '%s! exit %s: %s%s\n\n' "$R" "$rc" "$cmd" "$N"; fi
            fi ;;
          file_change)
            if [[ "$type" == item.completed ]]; then
              jq -r --arg pwd "$PWD/" '.item.changes[]? | "\(.kind) \(.path | ltrimstr($pwd))"' <<<"$line" 2>/dev/null |
                while IFS= read -r txt; do printf '%s+ %s%s\n' "$G" "$txt" "$N"; done
              printf '\n'
            fi ;;
          agent_message)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null)
              if [[ -n "$txt" ]]; then printf '%s%s%s\n\n' "$C" "$txt" "$N"; fi
            fi ;;
          reasoning)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-160)
              if [[ -n "$txt" ]]; then printf '%s* %s%s\n\n' "$D" "$txt" "$N"; fi
            fi ;;
          todo_list)
            txt=$(jq -r '[.item.items[]? | select(.completed == false)][0].text // empty' <<<"$line" 2>/dev/null)
            if [[ -n "$txt" ]]; then printf '%s> %s%s\n\n' "$D" "$txt" "$N"; fi ;;
        esac ;;
      turn.completed)
        txt=$(jq -r '"\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out"' <<<"$line" 2>/dev/null)
        printf '%sdone: %s%s\n\n' "$G" "$txt" "$N" ;;
      error)
        txt=$(jq -r '.message // "unknown error"' <<<"$line" 2>/dev/null)
        printf '%sERROR %s%s\n\n' "$R" "$txt" "$N" ;;
    esac
  done
  if [[ -n "$report" ]]; then printf '%sreport: %s%s\n' "$D" "$report" "$N"; fi
  return 0
}
```

      Dispatch: add `render) shift; render_stream "$@" ;;` to the bottom `case`.
      Display glyphs are plain ASCII (`$`, `!`, `+`, `*`, `>`); the demo's
      unicode `✓ ✖ • →` are fine too — pick one set and mirror it in tests
      (tests above assume the message text, not glyphs, except `$` and `exit 1:`).
- [ ] Run tests — 4 new pass, all old pass. `shellcheck plugin/scripts/codex-exec.sh` clean.
- [ ] Commit: `feat(codex-exec): render subcommand — condensed feed from codex --json stream`

## Task 2 — codex mock: JSONL branch, resume+--color rejection, failure branch

Files: `tests/helpers/bin/codex`.
TDD n/a — this IS test infrastructure; it is exercised red→green by task 3's
tests. Verification: full existing suite stays green after the change (no
current test passes `--json`, so the human branch still serves them).

- [ ] Extend the arg scan loop with `--json`/`--color` detection and add the
      rejection + failure + JSONL branches:

```bash
has_resume="" has_s="" has_json="" has_color=""
for a in "$@"; do
  [[ "$a" == "resume" ]] && has_resume=1
  [[ "$a" == "-s" ]] && has_s=1
  [[ "$a" == "--json" ]] && has_json=1
  [[ "$a" == "--color" ]] && has_color=1
done
if [[ -n "$has_resume" && -n "$has_s" ]]; then
  echo "error: unexpected argument '-s' found" >&2
  exit 2
fi
if [[ -n "$has_resume" && -n "$has_color" ]]; then
  echo "error: unexpected argument '--color' found" >&2
  exit 2
fi
```

      after the stdin drain, replace the two output echoes with:

```bash
if [[ -n "${MOCK_CODEX_FAIL:-}" ]]; then
  echo "Not inside a trusted directory and --skip-git-repo-check was not specified."
  exit "$MOCK_CODEX_FAIL"
fi
if [[ -n "$has_json" ]]; then
  echo '{"type":"thread.started","thread_id":"0000-mock-session"}'
  echo '{"type":"item.started","item":{"id":"i0","type":"command_execution","command":"echo hi","status":"in_progress"}}'
  echo '{"type":"item.completed","item":{"id":"i0","type":"command_execution","command":"echo hi","aggregated_output":"hi","exit_code":0,"status":"completed"}}'
  echo "{\"type\":\"item.completed\",\"item\":{\"id\":\"i1\",\"type\":\"file_change\",\"changes\":[{\"path\":\"$PWD/mock.txt\",\"kind\":\"add\"}],\"status\":\"completed\"}}"
  echo '{"type":"item.completed","item":{"id":"i2","type":"agent_message","text":"mock final message"}}'
  echo '{"type":"turn.completed","usage":{"input_tokens":100,"output_tokens":10}}'
else
  echo "session id: 0000-mock-session"
  echo "codex mock ran"
fi
```

      (report writing via `-o` stays as is — both branches keep it.)
- [ ] Run full suite — green (mock change alone breaks nothing).
- [ ] Commit: `test(mock): codex mock speaks --json, rejects resume+--color, can fail on demand`

## Task 3 — runner: `--json` + render pipe + prompt echo

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Consumes `render_stream` (task 1) and the mock JSONL branch (task 2).
Interface produced: runner script shape asserted by tests —
`codex exec … --json -o <out> - < <prompt> 2>&1 | <SCRIPT_DIR>/codex-exec.sh render <log> <out>`.

- [ ] Update existing assertions to expect the new shape (red first):
  - `run codex args` test: extend the final `[[ ]]` with `&& "$output" == *"--json"*`
  - `run tmux mode` test: in the `cat "$TMP/r1.run.sh"` assertion require
    `*"--json"*` and `*"codex-exec.sh render $TMP/r1.log"*`
  - `run resume` test: extend its runner assertion with `&& "$output" == *"--json"*`
  - `run background` test: add mid-test checks (before the final assertion):
    `[ "$(grep -c '^session id: ' "$TMP/r1.log")" = "1" ]` and
    `run bash -c "LC_ALL=C grep -q \$'\x1b' '$TMP/r1.log'"` → `[ "$status" -ne 0 ]`
- [ ] New test — sentinel carries a failing codex exit through the render pipe:

```bats
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
```

- [ ] Run — updated + new tests fail against the old runner.
- [ ] Implement: in `run_codex`, replace the heredoc body (keep everything else):

```bash
  cat > "$runner" <<EOF
#!/usr/bin/env bash
echo "=== $name ==="
$cd_line
printf '\e[2m--- prompt ---\n'
cat $prompt_file
printf '--------------\e[0m\n'
$codex_cmd $sandbox --json -o $out - < $prompt_file 2>&1 | $SCRIPT_DIR/codex-exec.sh render $log $out
echo "\${PIPESTATUS[0]}" > $sentinel
EOF
```

      (`$SCRIPT_DIR`, `$log`, `$out` expand at write time; prompt echo sits
      after `$cd_line` so a relative prompt path resolves exactly like codex's
      own `< $prompt_file`.)
- [ ] Run — all green. Live smoke NOT yet (task 5 does fresh+resume once).
- [ ] Commit: `feat(codex-exec): runner streams codex --json through render; prompt echoed in pane`

## Task 4 — pane placement + title (tmux, iTerm)

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.

- [ ] Update/add tests (red first):
  - `run tmux mode` test: replace the `tmux split-window` grep block with:

```bats
  run grep -F 'tmux split-window' "$RUN_LOG"
  [ "$status" -eq 0 ]
  grep -qF -- '-d -h -l 40%' <<<"$output"
  grep -qF "$TMP/r1.run.sh" <<<"$output"
  run grep -F 'tmux select-pane' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'-T codex-gpt-5.6-sol'* ]]
```

  - new iterm test:

```bats
@test "run iterm mode: split vertically, session named after agent" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out '$TMP/r1.md' --prompt-file '$TMP/p.txt' --visibility iterm"
  [ "$status" -eq 0 ]
  run grep -F 'osascript' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'iTerm2'* && "$output" == *'split vertically'* && "$output" == *'set name of newSession to "codex-gpt-5.6-sol"'* ]]
}
```

- [ ] Run — red (current code: `-v -l 15`, `split horizontally`, no titles).
- [ ] Implement in the `case "$vis"` block (add `local pane` to `run_codex` locals):

```bash
    tmux)
      echo 'sleep 10' >> "$runner"   # pane lingers so the human can read the tail
      pane="$(tmux split-window -d -h -l 40% -P -F '#{pane_id}' "$runner")"
      tmux select-pane -t "$pane" -T "$name" || true ;;
    iterm)
      osascript \
        -e 'tell application "iTerm2"' \
        -e 'tell current session of current window' \
        -e "set newSession to split vertically with default profile command \"$runner\"" \
        -e 'end tell' \
        -e "set name of newSession to \"$name\"" \
        -e 'end tell' >/dev/null ;;
```

      (title is best-effort → `|| true`; mock tmux prints nothing so `pane`
      is empty in tests — `select-pane -t ""` is still logged, which is what
      the test asserts.)
- [ ] Run — green. shellcheck clean.
- [ ] Commit: `feat(codex-exec): pane right at 40% + agent-name titles (tmux, iTerm)`

## Task 5 — version bump, full gate, live smoke

Files: `plugin/.claude-plugin/plugin.json`.
TDD n/a — release mechanics + the gotcha-mandated live verification.

- [ ] Bump version `0.1.19` → `0.1.20`.
- [ ] Full suite (running-tests skill) + `shellcheck plugin/scripts/*.sh` — green.
- [ ] Live smoke (codex gotcha doctrine — one real run per new arg shape),
      from a tmux session:
      `codex-exec.sh run --name codex-gpt-5.6-sol --model gpt-5.6-sol --out /tmp/s1.md --prompt-file <trivial prompt> --visibility tmux`
      → pane opens RIGHT, titled, condensed feed, sentinel `0`, log has one
      plain `session id:` line, report written. Then resume:
      `--resume "$(codex-exec.sh session-id /tmp/s1.log)"` → same checks.
      iTerm rung: manual, best-effort (spec).
- [ ] Commit: `chore(plugin): bump to 0.1.20`

## Self-review (done)

- every spec requirement maps: placement+title (T4), `--json` both shapes
  (T3, resume shape covered by existing resume test + `--json` assertion),
  hardened renderer + synthetic session line (T1), clean-log invariants
  (T1, T3), prompt echo (T3), blank lines between entries (T1 code),
  mock realism (T2), version bump + live smoke (T5).
- names consistent: `render_stream()` behind `render` subcommand;
  runner interface string identical in T1 (produced), T3 (asserted).
- bats gotcha respected: mid-test `[ ]`, decisive `[[ ]]` last.
- board: single PR → conveyor:executing-tasks directly, PR body `Fixes #<n>`
  (issue created at execution pickup).
