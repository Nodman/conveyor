# Plugin version stamp: session nudge after plugin updates

## What

Repos configured by conveyor carry a `pluginVersion` stamp; when the installed plugin is newer,
the SessionStart hook tells the user to run `/conveyor:doctor`. Doctor re-stamps and tells the
runner to commit the stamp, so the nudge self-clears — for every clone, not just the local
working tree. When the installed plugin is OLDER than the stamp (multi-dev repo: a teammate
upgraded and committed first), the hook instead says to update the plugin; doctor never
downgrades the stamp. (AMENDED 2026-07-12, #51.)

## Why

- After `claude plugin update`, nothing announces new behavior (e.g. 0.1.1's consent-gated label
  perms). Users who don't happen to run `/conveyor:work` (doctor at pickup) never find out.
- The plugin already injects SessionStart context — the right vehicle exists; it just isn't
  version-aware.

## Decisions (locked)

- Stamp lives in `.claude/conveyor.json` as top-level `"pluginVersion": "<semver>"`.
- Installed version = `jq -r .version <plugin root>/.claude-plugin/plugin.json` (resolved relative
  to the running script's own path — works from the cache copy).
- Nudge condition — AMENDED 2026-07-12 (#51), direction-aware via `sort -V`:
  `.claude/conveyor.json` exists AND stamp differs from installed. Stamp missing or older →
  doctor nudge (unchanged line). Stamp NEWER than installed → plugin-update nudge instead;
  running doctor must not downgrade. No conveyor.json → silent. Subagent sessions stay
  excluded (existing `agent_type` guard).
- Nudge is ONE line appended to the existing injected context. Doctor direction:
  `conveyor plugin updated <old|unstamped> → <new> since this repo was configured — run /conveyor:doctor to reconcile.`
  Plugin-behind direction:
  `this repo expects conveyor <stamped>, you have <installed> — run \`claude plugin update conveyor\`.`
- Re-stamp — AMENDED 2026-07-12 (#51): `board-doctor.sh` writes the installed version whenever
  installed > stamped, on EVERY run (the findings==0 gate was the #51 bug — any drift blocked
  the stamp, so the nudge never cleared). Never downgrades. When it stamps, it prints
  `board-doctor: stamped pluginVersion <old|unstamped> → <new> — commit .claude/conveyor.json`
  and the doctor skill commits the stamp (chore commit) so it propagates to other clones —
  an uncommitted stamp was the second half of #51: agents keep commits surgical and never
  picked it up.
- `init` writes the stamp when it writes config (skill prose: include `pluginVersion` from the
  plugin's plugin.json in step 4).
- Patch bump to 0.1.2 (per the plugin-dev rule in CLAUDE.md).

## Design

- `plugin/hooks/session-start.sh`: after the principles block, resolve installed version; if cwd
  has `.claude/conveyor.json` and stamp is absent/older, append the doctor nudge; if stamp is
  newer, append the plugin-update nudge (AMENDED 2026-07-12, #51). Direction via `sort -V`.
  Hook must stay fail-safe: any jq/read error → emit context without the nudge, exit 0.
- `plugin/scripts/board-doctor.sh`: before the findings check, if installed > stamped, jq-write
  `.pluginVersion = <installed>` back to `$CONVEYOR_CONFIG` (tmpfile + mv, preserve everything
  else) and print the commit reminder line (AMENDED 2026-07-12, #51).
- `plugin/skills/doctor/SKILL.md`: when the script reports a stamp update, commit
  `.claude/conveyor.json` as a chore commit (AMENDED 2026-07-12, #51).
- `plugin/skills/init/SKILL.md`: config step also sets `pluginVersion`.
- Tests (bats):
  - hooks: stamp == installed → no nudge; stamp missing / older → doctor nudge; stamp newer →
    plugin-update nudge, no doctor nudge; no conveyor.json → no nudge; subagent input → `{}`
    unchanged.
  - doctor: clean fixture run → conveyor.json gains pluginVersion == installed, other keys
    intact, output has commit reminder; drift fixture run → stamp STILL written (amended);
    stamp newer than installed → untouched, no reminder.
- Gate: full suite + shellcheck clean.

## Out of scope

- Auto-running doctor or auto-updating the plugin from the hook.
- Migration logic per version (changelogs, stepwise upgrades) — the nudge just points at doctor.
- Stamping from any script other than doctor (AMENDED 2026-07-12, #51: no longer clean-path-only).
- Auto-committing the stamp from the script itself — the skill/runner commits; scripts never
  run `git commit`.
