# Plugin version stamp: session nudge after plugin updates

## What

Repos configured by conveyor carry a `pluginVersion` stamp; when the installed plugin is newer,
the SessionStart hook tells the user to run `/conveyor:doctor`. Doctor re-stamps on a clean run,
so the nudge self-clears.

## Why

- After `claude plugin update`, nothing announces new behavior (e.g. 0.1.1's consent-gated label
  perms). Users who don't happen to run `/conveyor:work` (doctor at pickup) never find out.
- The plugin already injects SessionStart context — the right vehicle exists; it just isn't
  version-aware.

## Decisions (locked)

- Stamp lives in `.claude/conveyor.json` as top-level `"pluginVersion": "<semver>"`.
- Installed version = `jq -r .version <plugin root>/.claude-plugin/plugin.json` (resolved relative
  to the running script's own path — works from the cache copy).
- Nudge condition: `.claude/conveyor.json` exists AND (`pluginVersion` missing OR != installed).
  No conveyor.json → repo doesn't use conveyor → silent. Subagent sessions stay excluded
  (existing `agent_type` guard).
- Nudge is ONE line appended to the existing injected context:
  `conveyor plugin updated <old|unstamped> → <new> since this repo was configured — run /conveyor:doctor to reconcile.`
- Re-stamp: `board-doctor.sh` writes the installed version into the stamp only on a clean run
  (findings == 0). Known trade-off: script-clean stamps even if session-level skill checks (label
  perms, FILL markers) still have findings — those stay visible on every doctor run anyway; the
  stamp only silences the update nudge.
- `init` writes the stamp when it writes config (skill prose: include `pluginVersion` from the
  plugin's plugin.json in step 4).
- Patch bump to 0.1.2 (per the plugin-dev rule in CLAUDE.md).

## Design

- `plugin/hooks/session-start.sh`: after the principles block, resolve installed version; if cwd
  has `.claude/conveyor.json` and stamp is absent/older, append the nudge line to the emitted text.
  Hook must stay fail-safe: any jq/read error → emit context without the nudge, exit 0.
- `plugin/scripts/board-doctor.sh`: in the `findings -eq 0` branch, jq-write
  `.pluginVersion = <installed>` back to `$CONVEYOR_CONFIG` (tmpfile + mv, preserve everything else).
- `plugin/skills/init/SKILL.md`: config step also sets `pluginVersion`.
- Tests (bats):
  - hooks: stamp == installed → no nudge; stamp missing / older → nudge line present; no
    conveyor.json → no nudge; subagent input → `{}` unchanged.
  - doctor: clean fixture run → conveyor.json gains pluginVersion == installed, other keys intact;
    drift fixture run → stamp untouched.
- Gate: full suite + shellcheck clean.

## Out of scope

- Auto-running doctor or auto-updating the plugin from the hook.
- Migration logic per version (changelogs, stepwise upgrades) — the nudge just points at doctor.
- Stamping from any script other than doctor's clean path.
