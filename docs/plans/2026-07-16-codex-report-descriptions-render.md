# Codex report descriptions + human render — plan

Spec: `docs/specs/2026-07-16-codex-report-descriptions-render.md`.

**Goal:** pin report-field semantics via schema descriptions + a required
`message` field, and pretty-print the final JSON report in the pane in
default FG.

**Architecture:** two touch points. `plugin/config/report.schema.json` is
passed to codex via `--output-schema` (descriptions steer the model, shape
validates). `render_stream` in `plugin/scripts/codex-exec.sh` renders the
`--json` event stream; the final report arrives as an `agent_message` item
and is currently printed verbatim in the agent color. The report file
(`-o $out`) is written by codex itself — display changes never touch it.

**Global constraints:**

- Renderer runs under `set +e`; a display bug must never kill the codex run.
- Report block prints with NO color escapes (default FG) on tty and pipe.
- JSON without `verdict`, or unparsable text → today's raw agent-color path.
- Empty arrays render `none`, never omitted.
- Single PR; patch bump `plugin/.claude-plugin/plugin.json` 0.1.33 → 0.1.34.
- Style: short sentences; comments only for constraints code can't show.

## File map

| File | Responsibility |
|---|---|
| `plugin/config/report.schema.json` | field descriptions + required `message` |
| `plugin/scripts/codex-exec.sh` | `render_report()` + dispatch in `agent_message` branch |
| `tests/codex-exec.bats` | schema test + 3 render tests |
| `plugin/skills/routing/references/delegation-contract.md` | field list gains `message` |
| `plugin/.claude-plugin/plugin.json` | version 0.1.34 |
| `docs/specs/2026-07-16-codex-report-descriptions-render.md` | spec (already written, commits with T1) |
| `docs/plans/2026-07-16-codex-report-descriptions-render.md` | this plan (commits with T1) |
| `.claude/conveyor.json` | doctor version stamp riding along (commits with T1) |

## Task 1 — schema: descriptions + required `message`

Files: `plugin/config/report.schema.json`, `tests/codex-exec.bats`.
Produces: the six-field schema consumed by T2's renderer and by codex runs.

- [ ] Spec, plan, and `.claude/conveyor.json` stamp are uncommitted in the
      main checkout — copy these three files into the task worktree before
      starting (`cp` from the main checkout path).
- [ ] Write failing test (append to `tests/codex-exec.bats`):

```bash
@test "report schema: six required fields, every property described" {
  local schema="$SCRIPTS/../config/report.schema.json"
  run jq -e '.required == ["verdict","message","privileged_actions","denials","commit_shas","tests"]' "$schema"
  [ "$status" -eq 0 ]
  run jq -e '[.properties[] | .description // ""] | all(length > 0)' "$schema"
  [ "$status" -eq 0 ]
  run jq -e '.properties.message.type == "string"' "$schema"
  [ "$status" -eq 0 ]
}
```

- [ ] Run `bats tests/codex-exec.bats --filter "report schema"` — verify FAIL.
- [ ] Replace `plugin/config/report.schema.json` with:

```json
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "message", "privileged_actions", "denials", "commit_shas", "tests"],
  "properties": {
    "verdict": {
      "type": "string",
      "enum": ["approve", "request-changes", "comment"],
      "description": "Final review outcome."
    },
    "message": {
      "type": "string",
      "description": "Short human-readable summary of the run; lead with the reason for the verdict."
    },
    "privileged_actions": {
      "type": "array",
      "description": "Network/VCS commands actually run (gh, git push/fetch/commit, curl, ssh); empty if none.",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["command", "exit_code"],
        "properties": {
          "command": { "type": "string" },
          "exit_code": { "type": "integer" }
        }
      }
    },
    "denials": {
      "type": "array",
      "description": "Commands blocked by sandbox or policy; empty if none.",
      "items": { "type": "string" }
    },
    "commit_shas": {
      "type": "array",
      "description": "Commits created during this run; empty if none.",
      "items": { "type": "string" }
    },
    "tests": {
      "type": "array",
      "description": "Exact test commands run and their pass/fail result; empty if no tests were run. Never prose about what was inspected.",
      "items": { "type": "string" }
    }
  }
}
```

- [ ] Run the filter — verify PASS.
- [ ] Commit (includes spec, plan, `.claude/conveyor.json` stamp):
  `feat(codex): report schema — field descriptions + required message`

## Task 2 — renderer: pretty-print the report, default FG

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Consumes: T1 field set. Interface produced: `render_report <json-text>`
(prints block, returns 0; caller falls back on nonzero).

- [ ] Write failing tests (append to `tests/codex-exec.bats`):

```bash
@test "render: schema report pretty-printed, default FG, none for empty arrays" {
  local rpt='{"verdict":"comment","message":"Plan holds; two nits.","privileged_actions":[{"command":"gh pr view 12","exit_code":0}],"denials":[],"commit_shas":[],"tests":["bats tests/ — pass"]}'
  jq -nc --arg t "$rpt" '{"type":"item.completed","item":{"type":"agent_message","text":$t}}' > "$TMP/rp.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/rp.log' '' 35 < '$TMP/rp.jsonl'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Plan holds; two nits.'* ]]
  [[ "$output" == *'verdict: comment'* ]]
  [[ "$output" == *'tests: bats tests/ — pass'* ]]
  [[ "$output" == *'privileged: gh pr view 12 (exit 0)'* ]]
  [[ "$output" == *'commits: none'* && "$output" == *'denials: none'* ]]
  colored="$(printf '\033[35mPlan holds')"
  [ "$output" = "${output#*"$colored"}" ]   # message NOT in agent color
  [[ "$output" != *'"verdict"'* ]]          # raw JSON not shown
}

@test "render: JSON without verdict falls back to raw agent-color path" {
  jq -nc '{"type":"item.completed","item":{"type":"agent_message","text":"{\"note\":\"just json\"}"}}' > "$TMP/rf.jsonl"
  run_pty "'$SCRIPTS/codex-exec.sh' render '$TMP/rf.log' '' 35 < '$TMP/rf.jsonl'"
  [ "$status" -eq 0 ]
  raw_expected="$(printf '\033[35m{"note":"just json"}\033[0m')"
  [ "$output" != "${output#*"$raw_expected"}" ]
}
```

  (Plain-text regression is already covered by the existing
  "third argument sets command and agent-message color" test.)

- [ ] Run `bats tests/codex-exec.bats --filter "render"` — new tests FAIL,
      existing render tests PASS.
- [ ] Implement in `codex-exec.sh`. Add above `render_stream`:

```bash
render_report() {
  # default FG on purpose: report block must stand out from the agent-color wall
  jq -er '
    def list(f): if length == 0 then "none" else map(f) | join("; ") end;
    (.message // empty),
    "verdict: \(.verdict)",
    "tests: \(.tests // [] | list(.))",
    "commits: \(.commit_shas // [] | list(.))",
    "privileged: \(.privileged_actions // [] | list("\(.command) (exit \(.exit_code))"))",
    "denials: \(.denials // [] | list(.))"
  ' <<<"$1" 2>/dev/null
}
```

  Replace the `agent_message` branch body:

```bash
          agent_message)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null)
              if [[ -n "$txt" ]]; then
                if jq -e '.verdict? // empty | length > 0' >/dev/null 2>&1 <<<"$txt" && render_report "$txt"; then
                  printf '\n'
                else
                  printf '%s%s%s\n\n' "$C" "$txt" "$N"
                fi
              fi
            fi ;;
```

- [ ] Run `bats tests/codex-exec.bats` (full file) — verify PASS.
- [ ] Commit: `feat(codex): pretty-print final report in pane, default FG`

## Task 3 — docs + version bump

Files: `plugin/skills/routing/references/delegation-contract.md`,
`plugin/.claude-plugin/plugin.json`. TDD n/a: prose + version metadata; the
verification step is the full suite green.

- [ ] In `delegation-contract.md` line 50, change the field list to
  `(fields: verdict, message, privileged_actions, denials, commit_shas, tests)`.
- [ ] `plugin/.claude-plugin/plugin.json`: `"version": "0.1.34"`.
- [ ] Run full suite per running-tests skill — verify green.
- [ ] Commit: `chore(codex): document message field, bump plugin to 0.1.34`

## Self-review

- Spec requirement → task: descriptions (T1), required message (T1), pretty
  render + default FG + none + fallback (T2), report file untouched (T2 —
  renderer only), docs field list (T3), patch bump (T3). All covered.
- Names consistent: `render_report` used in T2 tests via behavior, not name;
  schema path `plugin/config/report.schema.json` everywhere.
- Board: single-PR plan → straight to executing-tasks.
