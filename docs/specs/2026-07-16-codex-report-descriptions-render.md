# Codex report: field descriptions, message field, human render — spec

## What

- `plugin/config/report.schema.json`: add per-field `description`s and a new
  required `message` string field.
- `codex-exec.sh render_stream`: pretty-print the final schema-shaped JSON
  report in the pane, default FG color. Report file stays raw JSON.

## Why

- Observed (plan-review run): `tests` carried the model's verification
  narrative — schema enforces shape, nothing defines meaning, so the model
  fills required fields with plausible prose.
- The pane prints the final agent message verbatim, so the human sees a raw
  JSON wall.
- User wants the prose summary kept (as `message`) and visually separated
  from the agent-colored output stream.

## Decisions (locked)

- **Schema descriptions** (steer the model; no validation change):
  - `verdict` — final review outcome.
  - `message` — short human-readable summary of the run; lead with the
    reason for the verdict. Required.
  - `privileged_actions` — network/VCS commands actually run (command +
    exit code); empty if none.
  - `denials` — commands blocked by sandbox/policy; empty if none.
  - `commit_shas` — commits created this run; empty if none.
  - `tests` — exact test commands run and their pass/fail result; empty
    array if no tests were run. Never prose about what was inspected.
- **`message` is required** so every report keeps a prose summary instead of
  hijacking `tests`.
- **Renderer**: in the `agent_message` branch, text that parses as JSON with
  a `verdict` key renders as:

  ```
  <message>
  verdict: <verdict>
  tests: <items | none>
  commits: <items | none>
  privileged: <cmd (exit N) | none>
  denials: <items | none>
  ```

  - Whole block in default FG (one visual unit, distinguishable from the
    agent-color wall). Non-JSON agent messages unchanged (agent color).
  - Empty arrays print `none` — explicit audit value, silence ≠ checked.
  - Parse failure or missing `verdict` → fall back to today's raw print.
- **Report file untouched**: `-o $out` keeps raw JSON; only pane display
  changes. Spawner-side parsing keeps working.
- **Docs**: add `message` to the field list in
  `plugin/skills/routing/references/delegation-contract.md`.
- **Version**: patch bump `plugin/.claude-plugin/plugin.json`.

## Design notes

- Detection: `jq -e '.verdict' <<<"$txt"` on the `agent_message` completed
  text; jq failure → raw path. Display bug must never kill the run
  (`set +e` already in place).
- `privileged_actions` items are objects → render `command (exit N)`.
- Old-schema reports (no `message`) still render: message line just absent.

## Testing

bats (`tests/codex-exec.bats`), mocks mirroring real stream shapes:

- Schema file: valid JSON; `required` includes all six fields; every
  property has a non-empty `description`.
- Render: final `agent_message` with schema-shaped JSON → pretty block,
  `message` first, `none` for empty arrays, no agent-color escape around
  the block.
- Render: non-JSON agent message → verbatim, agent color (regression).
- Render: JSON without `verdict` → raw fallback.

## Out of scope

- Semantic validation of report contents (model may still write weak
  messages; descriptions only steer).
- Changing spawn prompts or verdict transport (pr-reviewer COMMENT+label
  rule untouched).
- Coloring verdict by outcome.
