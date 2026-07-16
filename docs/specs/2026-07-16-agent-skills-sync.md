# Agent skills: sync-and-commit — spec

Issue #91. User ruling 2026-07-16, supersedes the symlink + gitignore design
(and the interim `.git/info/exclude` sketch in #91 comments).

## What

`link-agent-skills.sh` stops symlinking and gitignoring; it COPIES skill
sources into `.agents/skills/` as plain committed files.

## Why

- codex resolves `.agents/skills` per root; committed copies exist in every
  worktree, clone, and CI checkout — the per-worktree relink step disappears.
- `.agents/skills/` must be committable: contributors place real skills
  there. Symlinks (machine-local cache paths) and `.gitignore` entries block
  that.
- One mechanism (copy + existing staleness check) instead of three
  (symlink + ignore + per-root relink).

## Decisions (locked)

- **Sources** (unchanged): plugin skills `test-driven-development`,
  `systematic-debugging`, `gotchas` from the plugin's `skills/` dir (resolved
  relative to the script, as today); every dir under `$ROOT/.claude/skills/`.
- **Sync (apply mode):** target missing, a symlink, or content-different →
  `rm -rf` target, `cp -R` source, report `synced .agents/skills/<name>`.
  Identical → silent.
- **check mode:** same conditions → `DRIFT: .agents/skills/<name> missing or
  stale — fix: link-agent-skills.sh`, exit 1, write nothing.
- **Never touch unrecognized dirs** in `.agents/skills/` (contributor
  skills) — either mode.
- **Source of truth:** plugin dir / `.claude/skills`. Hand-edits to copies
  are overwritten by apply (they read as stale).
- **Gitignore migration:** apply removes an exact `.agents/` line from
  `$ROOT/.gitignore` (report it); check flags it as DRIFT. No other
  `.gitignore` writes, ever.
- **Committed drift:** after apply the changes are ordinary dirty files —
  they ride with the next branch/PR (same convention as the doctor's
  pluginVersion stamp; never commit on the default branch).
- **Docs:** doctor SKILL.md (drift wording, "commits ride along"),
  executing-tasks SKILL.md (delete the per-worktree relink step),
  docs/DECISIONS.md ruling entry, gotchas note if codex.md mentions links.
- **This repo migrates in the same PR:** run the new script, commit real
  copies + `.gitignore` minus `.agents/`.
- Patch bump `plugin/.claude-plugin/plugin.json`.

## Design notes

- Content compare: `diff -rq src tgt` (exit 0 = identical). Symlink target →
  always stale (forces migration off symlinks).
- Script name stays `link-agent-skills.sh` — callers and docs keep working;
  rename adds churn without value.
- Source dir deleted later (e.g. project skill removed): its old copy is
  left alone — out of scope.

## Testing

Rewrite `tests/link-agent-skills.bats`: copies are real dirs; idempotent;
source edit → resync; hand-edit → overwritten; old symlink → replaced;
`.agents/` gitignore line removed (apply) / flagged (check); unrecognized
dir untouched; check writes nothing and exits 1 on drift; no `.gitignore`
file → none created.

## Out of scope

- Pruning copies whose source disappeared.
- codex config alternatives (search-path config; `--strict-config` risk).
- Retroactive migration of OTHER repos' `.gitignore` beyond the exact
  `.agents/` line.
