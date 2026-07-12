# Plan: plugin version stamp + session update nudge

Spec: docs/specs/2026-07-11-plugin-version-stamp.md

**Goal:** sessions started under a newer plugin than the one that configured the repo get a one-line nudge to run /conveyor:doctor; doctor re-stamps on a clean run.

**Architecture:** both the SessionStart hook and board-doctor resolve the installed version from their own script path (`../.claude-plugin/plugin.json` — verified present in the installed cache). The stamp is a top-level `pluginVersion` key in `.claude/conveyor.json`. Hook compares and appends; doctor writes on findings==0.

**Global constraints (from spec):**
- Nudge line, exactly: `conveyor plugin updated <stamped|unstamped> → <installed> since this repo was configured — run /conveyor:doctor to reconcile.`
- Silent when: no `.claude/conveyor.json`; stamp matches; version unresolvable (fail-safe, exit 0).
- Subagent guard unchanged (`agent_type` → `{}`).
- Doctor stamps ONLY on the clean path (findings == 0), preserving every other config key.
  (AMENDED 2026-07-12, #51 — superseded; see amendment below.)
- plugin.json 0.1.1 → 0.1.2.

## File map

| File | Responsibility |
|---|---|
| plugin/hooks/session-start.sh | resolve installed version; append nudge when stamp absent/older |
| tests/hooks.bats | 3 new tests: matching stamp silent, stale/missing stamp nudges, no-config silent |
| plugin/scripts/board-doctor.sh | clean branch jq-writes pluginVersion into $CONVEYOR_CONFIG |
| tests/board-doctor.bats | 2 new tests: clean run stamps + preserves keys; drift run doesn't |
| plugin/skills/init/SKILL.md | config step includes pluginVersion |
| plugin/.claude-plugin/plugin.json | version 0.1.2 |

## Task 1 — session-start nudge

Files: `plugin/hooks/session-start.sh`, `tests/hooks.bats`.
Interfaces produced: nudge line format above; reads `.pluginVersion` from cwd's `.claude/conveyor.json`.

- [ ] Write failing tests — append to `tests/hooks.bats` (note: this file does NOT load helpers/env; each test makes its own tmp dir):

```bash
@test "session-start: conveyor repo with matching stamp → no nudge" {
  t="$(mktemp -d)"; mkdir -p "$t/.claude"
  v="$(jq -r .version "$BATS_TEST_DIRNAME/../plugin/.claude-plugin/plugin.json")"
  printf '{"pluginVersion":"%s"}' "$v" > "$t/.claude/conveyor.json"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"working principles"* ]]
  [[ "$ctx" != *"run /conveyor:doctor to reconcile"* ]]
  rm -rf "$t"
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
  [[ "$ctx" == *"conveyor plugin updated unstamped → "* ]]
  rm -rf "$t"
}

@test "session-start: no conveyor.json → no nudge" {
  t="$(mktemp -d)"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"working principles"* ]]
  [[ "$ctx" != *"reconcile"* ]]
  rm -rf "$t"
}
```

- [ ] `bats tests/hooks.bats` → the two nudge assertions fail.
- [ ] Implement — in `session-start.sh`, between the heredoc and the final `jq -n` emit:

```bash
if [[ -f .claude/conveyor.json ]]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  installed="$(jq -r '.version // empty' "$here/../.claude-plugin/plugin.json" 2>/dev/null || true)"
  stamped="$(jq -r '.pluginVersion // empty' .claude/conveyor.json 2>/dev/null || true)"
  if [[ -n "$installed" && "$stamped" != "$installed" ]]; then
    text+=$'\n\n'"conveyor plugin updated ${stamped:-unstamped} → $installed since this repo was configured — run /conveyor:doctor to reconcile."
  fi
fi
```

- [ ] `bats tests/hooks.bats` → all pass (incl. existing subagent/malformed tests); `bats tests` green; shellcheck clean (session-start.sh is in the repo shellcheck set via plugin/hooks/*.sh).
- [ ] Commit: `feat(hooks): session-start nudges /conveyor:doctor when plugin is newer than repo stamp`

## Task 2 — doctor stamps on clean run

Files: `plugin/scripts/board-doctor.sh`, `tests/board-doctor.bats`.
Interfaces consumed: same `pluginVersion` key and `../.claude-plugin/plugin.json` resolution as Task 1.

- [ ] Write failing tests — append to `tests/board-doctor.bats`:

```bash
# ---- pluginVersion stamp ---------------------------------------------------

@test "clean run stamps pluginVersion and preserves other keys" {
  use_cfg
  before_owner="$(jq -r .owner "$TMP/.claude/conveyor.json")"
  run_doctor doctor-clean
  [ "$status" -eq 0 ]
  v="$(jq -r .version "$BATS_TEST_DIRNAME/../plugin/.claude-plugin/plugin.json")"
  [ "$(jq -r .pluginVersion "$TMP/.claude/conveyor.json")" = "$v" ]
  [ "$(jq -r .owner "$TMP/.claude/conveyor.json")" = "$before_owner" ]
}

@test "drift run leaves pluginVersion untouched" {
  setup_drift
  run_doctor doctor-drift
  [ "$status" -eq 1 ]
  [ "$(jq -r '.pluginVersion // "absent"' "$TMP/.claude/conveyor.json")" = "absent" ]
}
```

- [ ] `bats tests/board-doctor.bats` → stamp test fails.
- [ ] Implement — in `board-doctor.sh`, extend the clean branch (keep message/exit unchanged):

```bash
if [[ "$findings" -eq 0 ]]; then
  installed="$(jq -r '.version // empty' "$HERE/../.claude-plugin/plugin.json" 2>/dev/null || true)"
  if [[ -n "$installed" ]]; then
    tmp=$(mktemp)
    jq --arg v "$installed" '.pluginVersion = $v' "$CONVEYOR_CONFIG" > "$tmp" && mv "$tmp" "$CONVEYOR_CONFIG"
  fi
  echo "board-doctor: no drift ($(jq length <<<"$items") issue cards checked)"
  exit 0
fi
```

- [ ] `bats tests` → full suite green; shellcheck clean.
- [ ] Commit: `feat(doctor): stamp pluginVersion into conveyor.json on clean runs`

## Task 3 — init prose + version bump

Files: `plugin/skills/init/SKILL.md`, `plugin/.claude-plugin/plugin.json`.
TDD n/a (prose + version constant); verification instead.

- [ ] init/SKILL.md, step 4 (Config): after "Verify every status key has an id." append:

```markdown
   Include `"pluginVersion"`: the installed plugin's version
   (`jq -r .version ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`) — the
   session-start hook compares it to nudge `/conveyor:doctor` after updates.
```

- [ ] plugin.json: `"version": "0.1.1"` → `"0.1.2"`.
- [ ] Verify: `grep -q 'pluginVersion' plugin/skills/init/SKILL.md`; `jq -r .version plugin/.claude-plugin/plugin.json` = `0.1.2`; `bats tests` green (frontmatter/no-blockers structure tests still pass); shellcheck clean.
- [ ] Commit: `docs(init): stamp pluginVersion at config time; bump plugin to 0.1.2`

## Board mapping

Single PR → issue #22, conveyor:executing-tasks. QA runtime surface: session-start.sh + board-doctor.sh (both drivable live); init prose is structure-checked only.

## Amendment 2026-07-12 — #51: direction-aware nudge, always-stamp, commit step

Spec amendment: same-name spec, AMENDED bullets. Two bugs in the shipped design:
- stamp only wrote on findings==0 → any drift kept the nudge forever;
- stamp landed uncommitted and nothing said to commit it → never propagated to other clones,
  and a dev with an OLDER plugin than the committed stamp got a nonsense nudge
  ("updated 2.0 → 1.5") and doctor would downgrade the stamp (ping-pong).

### Task A1 — direction-aware session-start nudge

Files: `plugin/hooks/session-start.sh`, `tests/hooks.bats`.

- [ ] Failing tests — append to `tests/hooks.bats`:

```bash
@test "session-start: stamp newer than installed → plugin-update nudge, not doctor" {
  t="$(mktemp -d)"; mkdir -p "$t/.claude"
  printf '{"pluginVersion":"999.0.0"}' > "$t/.claude/conveyor.json"
  run bash -c "cd '$t' && printf '%s' '{\"source\":\"startup\"}' | '$HOOKS/session-start.sh'"
  [ "$status" -eq 0 ]
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"this repo expects conveyor 999.0.0"* ]]
  [[ "$ctx" == *"claude plugin update conveyor"* ]]
  [[ "$ctx" != *"run /conveyor:doctor to reconcile"* ]]
  rm -rf "$t"
}
```

- [ ] Implement — replace the `!=` branch in `session-start.sh`:

```bash
if [[ -n "$installed" && "$stamped" != "$installed" ]]; then
  if [[ -n "$stamped" && "$(printf '%s\n%s\n' "$installed" "$stamped" | sort -V | tail -n1)" == "$stamped" ]]; then
    text+=$'\n\n'"this repo expects conveyor $stamped, you have $installed — run \`claude plugin update conveyor\`."
  else
    text+=$'\n\n'"conveyor plugin updated ${stamped:-unstamped} → $installed since this repo was configured — run /conveyor:doctor to reconcile."
  fi
fi
```

- [ ] `bats tests/hooks.bats` green (existing stale/missing-stamp tests unchanged); shellcheck clean.

### Task A2 — doctor stamps on every run, upward only, with commit reminder

Files: `plugin/scripts/board-doctor.sh`, `tests/board-doctor.bats`.

- [ ] Tests — in `tests/board-doctor.bats`: INVERT "drift run leaves pluginVersion untouched"
      (drift run now stamps, exit still 1); add: clean run prints the commit reminder; stamp
      newer than installed (`"pluginVersion":"999.0.0"` in fixture cfg) → untouched, no reminder.
- [ ] Implement — delete the stamp block from the `findings -eq 0` branch; before the final
      findings check insert:

```bash
installed="$(jq -r '.version // empty' "$HERE/../.claude-plugin/plugin.json" 2>/dev/null || true)"
stamped="$(jq -r '.pluginVersion // empty' "$CONVEYOR_CONFIG" 2>/dev/null || true)"
if [[ -n "$installed" && "$stamped" != "$installed" && \
      "$(printf '%s\n%s\n' "$installed" "${stamped:-0}" | sort -V | tail -n1)" == "$installed" ]]; then
  tmp=$(mktemp)
  jq --arg v "$installed" '.pluginVersion = $v' "$CONVEYOR_CONFIG" > "$tmp" && mv "$tmp" "$CONVEYOR_CONFIG"
  echo "board-doctor: stamped pluginVersion ${stamped:-unstamped} → $installed — commit .claude/conveyor.json"
fi
```

- [ ] `bats tests/board-doctor.bats` green; full `bats tests` green; shellcheck clean.

### Task A3 — doctor skill commits the stamp; version bump

Files: `plugin/skills/doctor/SKILL.md`, `plugin/.claude-plugin/plugin.json`. TDD n/a (prose + constant).

- [ ] doctor SKILL.md step 3: when the script printed
      `stamped pluginVersion … — commit .claude/conveyor.json`, commit that one file:
      `git commit -m "chore: doctor — stamp pluginVersion <new>" .claude/conveyor.json`
      (no ask — it records the already-installed version; precedent 1055c1e).
- [ ] plugin.json 0.1.18 → 0.1.19.
- [ ] Verify: `bats tests` green; shellcheck clean.

### Board mapping (amendment)

Single PR → issue #51, conveyor:executing-tasks. QA surface: session-start.sh + board-doctor.sh, live-drivable.
