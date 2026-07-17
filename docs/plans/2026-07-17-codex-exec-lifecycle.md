# Plan: codex-exec lifecycle hardening

Spec: `docs/specs/2026-07-17-codex-exec-lifecycle.md` · Issue: #98 · Single PR.

**Goal:** fix resume model drop, validate reports before success, add
`kill`/`status`/`wait` on a write-once `.job` record, optional `--effort`,
prompt-clause folds, mock/test coverage.

**Architecture:** all runtime changes live in `plugin/scripts/codex-exec.sh`
(bash + jq, no new files, no daemon). State = files the runner already writes
plus one `.job` JSON written once at spawn. Skills/agents get prose edits only.

**Global constraints (from spec):**
- `--effort` absent → nothing passed. Enum: `minimal|low|medium|high|xhigh`.
- Sentinel codes: worker-only. `0` valid success, `97` missing/empty report,
  `98` report not JSON (only when `--output-schema` given). `kill` NEVER
  writes the sentinel.
- `status` output: `done <code>` | `running …` | `dead`. `wait` exits `0`
  (sentinel present), `3` (dead), `124` (timeout).
- Dumb kill: no pid-reuse identity check.
- Live-verify every new codex arg shape once before trusting the mock
  (`docs/gotchas/codex.md` rule).
- Bats law (`docs/gotchas/bats.md`): mid-test assertions use `[ ]` or
  `run`+status; the decisive `[[ ]]` goes last; never bare `!`-negation
  mid-test; scrub `TMUX` AND `TMUX_PANE` (the `$CX` helper does).

## File map

| File | Responsibility |
|---|---|
| `plugin/scripts/codex-exec.sh` | `--effort`, resume `-m`, report validation, `.job` record, `kill`/`status`/`wait`, usage text |
| `tests/helpers/bin/codex` | mock: slow / no-report / bad-report modes, schema-aware report body, resume `-m` contract |
| `tests/codex-exec.bats` | tests for all of the above |
| `docs/gotchas/codex.md` | live-verified results for `resume -m` and `model_reasoning_effort` |
| `plugin/skills/council/SKILL.md` | poll prose → `wait` call |
| `plugin/skills/executing-tasks/SKILL.md` | sentinel-wait prose → `wait`/`status`/`kill` |
| `plugin/skills/routing/references/delegation-contract.md` | prompt-rules clauses; runner contract mentions `wait` |
| `plugin/agents/pr-reviewer.md` | attack-surface / finding-bar / calibration / grounding clauses |
| `plugin/.claude-plugin/plugin.json` | version 0.1.35 → 0.1.36 |

## Task 1 — live-verify new arg shapes, record in gotchas

TDD n/a (live verification against the real CLI; this pins the contract the
mock will encode). Requires authed codex (`codex-exec.sh preflight` = ok).

- [ ] Fresh throwaway run in `/tmp` to get a session id:
      `codex exec -m gpt-5.6-sol --json -s read-only - <<< 'Reply DONE.'`
      (capture `thread.started` id).
- [ ] Verify resume model: `codex exec resume <sid> -m gpt-5.6-sol --json - <<< 'Reply DONE.'`
      Accepted → contract A (`resume` takes `-m`). Rejected (`unexpected
      argument`) → contract B: use `-c model="gpt-5.6-sol"` on resume; verify
      that shape live instead.
- [ ] Verify effort, fresh AND resume: append `-c model_reasoning_effort=high`
      to both commands above; confirm accepted (no config error, run completes).
- [ ] Append a `docs/gotchas/codex.md` section "resume model + reasoning
      effort (codex-cli <version>, 2026-07-17)" recording exact commands and
      results, mirroring the existing workspace-write entry style.
- [ ] Commit: `docs(gotchas): live-verify resume -m and model_reasoning_effort arg shapes`

All later tasks assume contract A; if B won, substitute `-c model="$model"`
for `-m $model` on the resume path everywhere below (tests included).

## Task 2 — resume model parity + `--effort`

Files: `plugin/scripts/codex-exec.sh`, `tests/helpers/bin/codex`,
`tests/codex-exec.bats`.
Produces: run flag `--effort <v>`; resume command carries the model.

- [ ] Mock first — encode the live-verified contract in `tests/helpers/bin/codex`.
      After the existing `has_resume`/`has_s` scan add:

```bash
# contract A live-verified 2026-07-17 (task 1): resume accepts -m
prev=""
for a in "$@"; do
  if [[ "$prev" == "-c" ]]; then
    key="${a%%=*}"; val="${a#*=}"
    if [[ "$key" == "model_reasoning_effort" ]]; then
      case "$val" in minimal|low|medium|high|xhigh) ;;
        *) echo "error: invalid value '$val' for model_reasoning_effort" >&2; exit 1 ;;
      esac
    fi
  fi
  prev="$a"
done
```

- [ ] Write failing tests (append to `tests/codex-exec.bats`):

```bash
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
```

- [ ] Run `bats tests/codex-exec.bats`, verify the four fail.
- [ ] Implement in `run_codex()`:
  - locals: add `effort=""`; arg loop: `--effort) effort="$2"; shift 2 ;;`.
  - after sandbox validation: `case "$effort" in ""|minimal|low|medium|high|xhigh) ;; *) usage ;; esac`.
  - build: `local effort_flag=""; [[ -n "$effort" ]] && effort_flag="-c model_reasoning_effort=$effort"`.
  - line 201: `local codex_cmd="codex exec -m $model $search $effort_flag" sandbox="-s $sandbox_mode"`.
  - line 203 resume: `codex_cmd="codex exec resume $resume -m $model $search $effort_flag"`.
  - usage(): add `[--effort minimal|low|medium|high|xhigh]` to the run line.
- [ ] Run suite, verify pass (existing resume tests still green — they assert
      substrings, `-m` insertion doesn't break them).
- [ ] Commit: `fix(codex-exec): resume keeps -m; optional --effort flag (#98)`

## Task 3 — report validation before sentinel

Files: `plugin/scripts/codex-exec.sh`, `tests/helpers/bin/codex`,
`tests/codex-exec.bats`.
Produces: sentinel codes 97/98; consumed by Task 6 tests.

- [ ] Mock: add failure modes. Before the `has_json` emit block:

```bash
if [[ -n "${MOCK_CODEX_SLOW:-}" ]]; then sleep "$MOCK_CODEX_SLOW"; fi
```

  and replace the final report write (`if [[ -n "$out" ]]; then …`) with:

```bash
has_schema=""
for a in "$@"; do [[ "$a" == "--output-schema" ]] && has_schema=1; done
if [[ -n "$out" && -z "${MOCK_CODEX_NO_REPORT:-}" ]]; then
  if [[ -n "${MOCK_CODEX_BAD_REPORT:-}" ]]; then
    printf 'not json{\n' > "$out"
  elif [[ -n "$has_schema" ]]; then
    printf '{"verdict":"comment","message":"mock","privileged_actions":[],"denials":[],"commit_shas":[],"tests":[]}\n' > "$out"
  else
    printf 'mock final message\n' > "$out"
  fi
fi
```

- [ ] Failing tests:

```bash
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
```

- [ ] Verify fail (97/98 tests; the third passes only after the mock change —
      keep it, it pins the schema-aware mock body).
- [ ] Implement — runner heredoc (codex-exec.sh:220-221). Replace:

```bash
$codex_cmd $sandbox $schema_flag --json -o $out - < $prompt_file 2>&1 | $SCRIPT_DIR/codex-exec.sh render $log $out $color
echo "\${PIPESTATUS[0]}" > $sentinel
```

  with:

```bash
$codex_cmd $sandbox $schema_flag --json -o $out - < $prompt_file 2>&1 | $SCRIPT_DIR/codex-exec.sh render $log $out $color
rc="\${PIPESTATUS[0]}"
if [[ "\$rc" == 0 && ! -s $out ]]; then echo "FAIL: no report at $out" >> $log; rc=97; fi
$schema_check
echo "\$rc" > $sentinel
```

  where above the heredoc:

```bash
local schema_check=""
[[ -n "$output_schema" ]] && schema_check="if [[ \"\$rc\" == 0 ]] && ! jq -e . $out >/dev/null 2>&1; then echo \"FAIL: report not valid JSON: $out\" >> $log; rc=98; fi"
```

- [ ] Run suite, verify pass. Note: the existing tmux-mode test asserts
      `> $TMP/r1.md.done` appears in the runner — still true.
- [ ] Commit: `fix(codex-exec): sentinel 0 requires a usable report (97/98 otherwise) (#98)`

## Task 4 — write-once `.job` spawn record

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Produces: `${out%.md}.job` JSON — fields `name model mode out log sentinel
created` + `pid` (background) / `pane` (tmux) / `workdir` (when set).
Consumed by Tasks 5/6.

- [ ] Failing tests:

```bash
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
  grep -qF "job=$TMP/j1.job" <<<"$(cd "$TMP" && $CX "$SCRIPTS/codex-exec.sh" run --name n --model m --out "$TMP/j2.md" --prompt-file "$TMP/p.txt")"
}

@test "run tmux mode: .job record has pane id" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX TMUX_PANE=%1 MOCK_TMUX_LAYOUT=no-split '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/j3.md' --prompt-file '$TMP/p.txt' --visibility tmux"
  [ "$status" -eq 0 ]
  run jq -r .pane "$TMP/j3.job"
  [ "$output" = "%99" ]
}
```

  (`%99` is what the tmux mock returns for `split-window -P` — confirm against
  `tests/helpers/bin/tmux` and adjust the literal if different.)

- [ ] Verify fail. Implement in `run_codex()`:
  - `local job="${out%.md}.job"`; `rm -f … "$job"` at the existing cleanup line.
  - in the visibility `case`: background arm becomes
    `nohup "$runner" >/dev/null 2>&1 & pid=$!` (add `local pid=""` up top).
  - after the `case`, before the final printf:

```bash
jq -n --arg name "$name" --arg model "$model" --arg mode "$vis" \
  --arg out "$out" --arg log "$log" --arg sentinel "$sentinel" \
  --arg workdir "$workdir" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg pid "${pid:-}" --arg pane "${pane:-}" \
  '{name:$name, model:$model, mode:$mode, out:$out, log:$log,
    sentinel:$sentinel, created:$created}
   + (if $workdir != "" then {workdir:$workdir} else {} end)
   + (if $pid != "" then {pid:($pid|tonumber)} else {} end)
   + (if $pane != "" then {pane:$pane} else {} end)' > "$job"
```

  - extend the final printf with `job=%s\n` (+ arg `"$job"`).
- [ ] Run suite, verify pass.
- [ ] Commit: `feat(codex-exec): write-once .job spawn record (#98)`

## Task 5 — `kill` subcommand

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Interface: `codex-exec.sh kill <report.md>`; reads `.job`, never writes the
sentinel.

- [ ] Failing tests:

```bash
@test "kill: background run TERMs codex, worker writes 143 sentinel" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_SLOW=60 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/k1.md' --prompt-file '$TMP/p.txt'"
  [ "$status" -eq 0 ]
  sleep 1   # let the runner reach codex
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
```

  (First test asserts nonzero, not exactly 143: TERM lands on the mock's
  `sleep`, and bash reports 143; but if the grace path escalates it can be
  137. Pin only "not 0" — the point is the WORKER wrote it.)

- [ ] Verify fail. Implement:

```bash
kill_run() {
  local out="${1:?}" job sentinel; job="${out%.md}.job"; sentinel="$out.done"
  [[ -f "$job" ]] || die "no job record: $job"
  if [[ -f "$sentinel" ]]; then echo "already done ($(cat "$sentinel"))"; return 0; fi
  local mode pid pane
  mode="$(jq -r .mode "$job")"; pid="$(jq -r '.pid // empty' "$job")"; pane="$(jq -r '.pane // empty' "$job")"
  case "$mode" in
    background)
      [[ -n "$pid" ]] || die "no pid in $job"
      # TERM the runner's children (codex + render), NOT the runner: it must
      # survive to write the sentinel from PIPESTATUS
      pkill -TERM -P "$pid" 2>/dev/null || true
      local i; for i in $(seq 1 20); do [[ -f "$sentinel" ]] && break; sleep 0.5; done
      if [[ ! -f "$sentinel" ]]; then
        pkill -KILL -P "$pid" 2>/dev/null || true
        kill -KILL "$pid" 2>/dev/null || true
      fi
      echo "killed pid=$pid" ;;
    tmux)
      [[ -n "$pane" ]] || die "no pane in $job"
      tmux kill-pane -t "$pane" 2>/dev/null || true
      echo "killed pane=$pane (no sentinel — pane died with the runner)" ;;
    *) die "kill unsupported for mode=$mode — close it by hand" ;;
  esac
}
```

  Dispatch: `kill) shift; kill_run "$@" ;;` + usage line
  `codex-exec.sh kill <report.md>`.
- [ ] Run suite, verify pass.
- [ ] Commit: `feat(codex-exec): kill subcommand — stop handle for full-access runs (#98)`

## Task 6 — `status` + `wait` subcommands

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Interface: `status <report.md>` → `done <code>` | `running pid=…|pane=… log_age=<s>s`
| `dead`; `wait <report.md> [--timeout <s>]` (default 540) → exit 0/3/124.

- [ ] Failing tests:

```bash
@test "status: done → done <code>" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s3.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/s3.md.done"
  run bash -c "'$SCRIPTS/codex-exec.sh' status '$TMP/s3.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "done 0" ]
}

@test "status: live background run → running with pid and log_age" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_SLOW=60 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s4.md' --prompt-file '$TMP/p.txt'"
  sleep 1
  run bash -c "'$SCRIPTS/codex-exec.sh' status '$TMP/s4.md'"
  [ "$status" -eq 0 ]
  bash -c "'$SCRIPTS/codex-exec.sh' kill '$TMP/s4.md'" || true
  [[ "$output" == running\ pid=*log_age=* ]]
}

@test "status: dead pid, no sentinel → dead" {
  use_cfg
  jq -n --arg out "$TMP/s5.md" '{name:"n",model:"m",mode:"background",out:$out,log:($out|sub("\\.md$";".log")),sentinel:($out+".done"),created:"2026-07-17T00:00:00Z",pid:99999999}' > "$TMP/s5.job"
  run bash -c "'$SCRIPTS/codex-exec.sh' status '$TMP/s5.md'"
  [ "$status" -eq 0 ]
  [ "$output" = "dead" ]
}

@test "wait: returns 0 when sentinel lands, prints done" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_SLOW=2 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s6.md' --prompt-file '$TMP/p.txt'"
  run bash -c "'$SCRIPTS/codex-exec.sh' wait '$TMP/s6.md' --timeout 30"
  [ "$status" -eq 0 ]
  [ "$output" = "done 0" ]
}

@test "wait: dead run → exit 3" {
  use_cfg
  jq -n --arg out "$TMP/s7.md" '{name:"n",model:"m",mode:"background",out:$out,log:($out|sub("\\.md$";".log")),sentinel:($out+".done"),created:"2026-07-17T00:00:00Z",pid:99999999}' > "$TMP/s7.job"
  run bash -c "'$SCRIPTS/codex-exec.sh' wait '$TMP/s7.md' --timeout 30"
  [ "$status" -eq 3 ]
  [ "$output" = "dead" ]
}

@test "wait: timeout → exit 124" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX MOCK_CODEX_SLOW=60 '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/s8.md' --prompt-file '$TMP/p.txt'"
  run bash -c "'$SCRIPTS/codex-exec.sh' wait '$TMP/s8.md' --timeout 1"
  code="$status"
  bash -c "'$SCRIPTS/codex-exec.sh' kill '$TMP/s8.md'" || true
  [ "$code" -eq 124 ]
}
```

- [ ] Verify fail. Implement:

```bash
status_run() {
  local out="${1:?}" job sentinel; job="${out%.md}.job"; sentinel="$out.done"
  if [[ -f "$sentinel" ]]; then echo "done $(cat "$sentinel")"; return 0; fi
  [[ -f "$job" ]] || die "no run for $out"
  local mode pid pane log age="?"
  mode="$(jq -r .mode "$job")"; pid="$(jq -r '.pid // empty' "$job")"
  pane="$(jq -r '.pane // empty' "$job")"; log="$(jq -r .log "$job")"
  if [[ -f "$log" ]]; then
    age="$(( $(date +%s) - $(stat -f %m "$log" 2>/dev/null || stat -c %Y "$log") ))"
  fi
  case "$mode" in
    background)
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "running pid=$pid log_age=${age}s"
      else echo dead; fi ;;
    tmux)
      if [[ -n "$pane" ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane"; then
        echo "running pane=$pane log_age=${age}s"
      else echo dead; fi ;;
    *) echo "running mode=$mode (no handle)" ;;   # window/iterm: can't probe
  esac
}

wait_run() {
  local out="${1:?}"; shift
  local timeout=540
  while [[ $# -gt 0 ]]; do
    case "$1" in --timeout) timeout="$2"; shift 2 ;; *) usage ;; esac
  done
  local sentinel="$out.done" deadline=$(( $(date +%s) + timeout )) s
  while true; do
    if [[ -f "$sentinel" ]]; then echo "done $(cat "$sentinel")"; return 0; fi
    s="$(status_run "$out")"
    if [[ "$s" == dead ]]; then echo dead; return 3; fi
    if (( $(date +%s) >= deadline )); then echo timeout; return 124; fi
    sleep 5
  done
}
```

  Dispatch + usage lines for both. Note `stat -f %m` (macOS) with `stat -c %Y`
  fallback (Linux CI).
- [ ] Run suite, verify pass.
- [ ] Commit: `feat(codex-exec): status + wait subcommands (#98)`

## Task 7 — skill prose: replace hand-rolled polling

Files: `plugin/skills/council/SKILL.md`,
`plugin/skills/executing-tasks/SKILL.md`,
`plugin/skills/routing/references/delegation-contract.md`.
TDD n/a (markdown). Verification: `grep` assertions below.

- [ ] council SKILL.md step 2 — replace
      "Wait on sentinels/agent returns; poll every ~15s, cap 15 minutes." with:
      "Wait: `codex-exec.sh wait <out> --timeout 540` per codex member
      (re-call once for the 15-min cap; claude members return via Agent).
      `dead`/timeout → `codex-exec.sh kill <out>`, drop that member and tell
      the user."
- [ ] executing-tasks SKILL.md — replace "Sentinel wait: poll ~15s; at ~15 min
      check liveness (log growth / visibility pane) — kill and resume by
      session id (`codex-exec.sh session-id <log>`) only on a dead log." with:
      "Sentinel wait: `codex-exec.sh wait <out> --timeout 540`, re-call while
      `status` shows `running`; `dead` → `codex-exec.sh kill <out>`, then
      resume by session id (`codex-exec.sh session-id <log>`)."
- [ ] delegation-contract.md external-runner contract — change "Explicit
      timeout + background poll on the sentinel." to "Explicit timeout via a
      bounded `wait` on the sentinel; a stop handle (`kill`) for live runs."
- [ ] Verify: `grep -rn 'poll ~15s\|poll every ~15s' plugin/` → no hits;
      `grep -c 'wait <out>' plugin/skills/council/SKILL.md` ≥ 1.
- [ ] Commit: `docs(skills): council/executing-tasks use codex-exec wait/kill (#98)`

## Task 8 — prompt folds (exact clauses from the spec)

Files: `plugin/agents/pr-reviewer.md`,
`plugin/skills/routing/references/delegation-contract.md`.
TDD n/a (markdown). Clause text is LOCKED in the spec — copy from spec item 6,
don't rephrase.

- [ ] pr-reviewer.md — in "## Process" step 3, after the "Correctness" bullet
      add:

```markdown
   - **Attack surface** — prioritize expensive/hard-to-detect failures: auth,
     permissions, trust boundaries; data loss, corruption, irreversible state;
     rollback, retries, partial failure, idempotency; races, ordering, stale
     state; empty/null/timeout/degraded-dependency paths; version skew, schema
     drift; observability gaps that hide failure.
```

      and after Process step 4 add:

```markdown
5. Finding bar: each finding answers what goes wrong, why this path is
   vulnerable, likely impact, concrete fix. One strong finding beats several
   weak ones — never dilute serious issues with filler. Findings must be
   defensible from the diff/code alone; a conclusion resting on inference says
   so explicitly.
```

- [ ] delegation-contract.md — new section after "## Spawn-prompt fields":

```markdown
## Prompt rules

- One task per run; unrelated asks are separate runs.
- Resume sends only the delta instruction, never the restated prompt, unless
  direction changed materially.
- Claims anchored to observed evidence; hypotheses labeled as such.
- Weak result → tighten the prompt contract before raising model/effort.
```

- [ ] Verify: `grep -c 'Attack surface' plugin/agents/pr-reviewer.md` = 1;
      `grep -c 'Prompt rules' plugin/skills/routing/references/delegation-contract.md` = 1.
- [ ] Commit: `docs(agents,routing): fold codex-plugin-cc prompt clauses (#98)`

## Task 9 — version bump, full suite, live smoke

Files: `plugin/.claude-plugin/plugin.json`.

- [ ] Bump version `0.1.35` → `0.1.36` (PR touches `plugin/`).
- [ ] `bats tests/` — full suite green.
- [ ] Live smoke (authed codex, one run each): fresh run with `--effort low`;
      `status` while running; `wait --timeout 60`; resume that session
      (confirm `-m` accepted live matches task 1); background run +
      `kill` mid-run → sentinel nonzero, non-`kill`-written. Record any
      surprise in `docs/gotchas/codex.md`.
- [ ] Commit: `chore(plugin): bump to 0.1.36 (#98)`

## Self-review

- Spec item 1 → tasks 1-2; item 2 → task 3; item 3 → tasks 4-5; item 4 →
  tasks 6-7; item 5 → task 2; item 6 → task 8; item 7 → tasks 2-6 mock/tests
  + task 9 live smoke. All covered.
- Names consistent: `.job` / `kill_run` / `status_run` / `wait_run`; sentinel
  codes 97/98; wait exits 0/3/124 used identically in tasks 3-6.
- Embedded tests checked against `docs/gotchas/bats.md`: mid-test assertions
  use `[ ]` or `run`+status; decisive `[[ ]]` placed last; no bare `!`
  mid-test (negations use `run` + `[ "$status" -ne 0 ]`); `$CX` scrubs
  `TMUX`+`TMUX_PANE`.
- Board: single PR → card #98 (`Fixes #98`), straight to executing-tasks.
