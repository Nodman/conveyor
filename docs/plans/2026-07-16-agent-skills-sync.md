# Agent skills sync-and-commit — plan

Spec: `docs/specs/2026-07-16-agent-skills-sync.md`. Issue #91.

**Goal:** `link-agent-skills.sh` copies skill sources into committed
`.agents/skills/`; no symlinks, no gitignore writes; this repo migrates in
the same PR.

**Architecture:** one script rewrite (`plugin/scripts/link-agent-skills.sh`,
same name and CLI: `[check]` arg, exit 1 on drift). Sources resolve as
today: plugin skills relative to the script, project skills from
`$ROOT/.claude/skills/`. Docs in two skills reference the old behavior and
change with it.

**Global constraints:**

- bats runs macOS bash 3.2 — no mapfile, no negative subscripts.
- check mode writes NOTHING.
- Unrecognized dirs under `.agents/skills/` are never touched.
- shellcheck clean (`plugin/scripts/*.sh`).
- Patch bump: `plugin/.claude-plugin/plugin.json` — set to one above
  whatever the branch's current value is after rebase (0.1.34 in main at
  plan time → 0.1.35; PR #93 also bumps, expect a one-line conflict; rebase
  on main before opening the PR and re-check).
- Style: short sentences; comments only for constraints code can't show.

## File map

| File | Responsibility |
|---|---|
| `plugin/scripts/link-agent-skills.sh` | sync_one copy logic, gitignore-line removal |
| `tests/link-agent-skills.bats` | full rewrite for copy semantics |
| `plugin/skills/doctor/SKILL.md` | drift wording: copies commit, ride with next PR |
| `plugin/skills/executing-tasks/SKILL.md` | delete per-worktree relink step |
| `docs/DECISIONS.md` | 2026-07-16 ruling entry |
| `.agents/skills/*`, `.gitignore` | this repo's migration (run the new script) |
| `plugin/.claude-plugin/plugin.json` | patch bump |
| `docs/specs/…-agent-skills-sync.md`, `docs/plans/…-agent-skills-sync.md` | ride along, commit with T1 |

## Task 1 — script rewrite + tests

Files: `plugin/scripts/link-agent-skills.sh`, `tests/link-agent-skills.bats`.
Produces: `link-agent-skills.sh [check]`, same exit contract, copy semantics.

- [ ] Copy the uncommitted spec + plan from the main checkout into the
      worktree first.
- [ ] Rewrite `tests/link-agent-skills.bats` (full file):

```bash
#!/usr/bin/env bats
load helpers/env

# link-agent-skills runs from the repo (or worktree) root; cwd is the root.

seed_tree() {
  mkdir -p "$TMP/.claude/skills/running-tests" "$TMP/.claude/skills/running-the-app"
  printf 'proj skill\n' > "$TMP/.claude/skills/running-tests/SKILL.md"
  printf 'node_modules/\n.agents/\n' > "$TMP/.gitignore"
}

@test "copies plugin and project skills as real dirs, drops .agents/ gitignore line" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  for name in test-driven-development systematic-debugging gotchas running-tests running-the-app; do
    [ -d "$TMP/.agents/skills/$name" ]
    [ ! -L "$TMP/.agents/skills/$name" ]
  done
  grep -qF 'synced .agents/skills/gotchas' <<<"$output"
  diff -rq "$SCRIPTS/../skills/gotchas" "$TMP/.agents/skills/gotchas"
  ! grep -qxF '.agents/' "$TMP/.gitignore"
  grep -qxF 'node_modules/' "$TMP/.gitignore"
}

@test "idempotent — second run silent" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "source edit resyncs; hand-edited copy overwritten" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  printf 'v2\n' > "$TMP/.claude/skills/running-tests/SKILL.md"
  printf 'hand edit\n' >> "$TMP/.agents/skills/running-the-app/SKILL.md" 2>/dev/null || printf 'hand edit\n' > "$TMP/.agents/skills/running-the-app/SKILL.md"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  grep -qF 'v2' "$TMP/.agents/skills/running-tests/SKILL.md"
  ! grep -qF 'hand edit' "$TMP/.agents/skills/running-the-app/SKILL.md"
}

@test "old symlink replaced by a real copy" {
  seed_tree
  mkdir -p "$TMP/.agents/skills"
  ln -sfn "$SCRIPTS/../skills/gotchas" "$TMP/.agents/skills/gotchas"
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ ! -L "$TMP/.agents/skills/gotchas" ]
  [ -f "$TMP/.agents/skills/gotchas/SKILL.md" ]
}

@test "unrecognized contributor dir untouched in both modes" {
  seed_tree
  mkdir -p "$TMP/.agents/skills/contrib-skill"
  printf 'theirs\n' > "$TMP/.agents/skills/contrib-skill/SKILL.md"
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 0 ]
  grep -qF 'theirs' "$TMP/.agents/skills/contrib-skill/SKILL.md"
}

@test "check mode: drift flagged, exit 1, nothing written" {
  seed_tree
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 1 ]
  grep -qF 'DRIFT: .agents/skills/test-driven-development missing or stale' <<<"$output"
  grep -qF 'DRIFT: .agents/ still gitignored' <<<"$output"
  [ ! -e "$TMP/.agents" ]
  grep -qxF '.agents/' "$TMP/.gitignore"
}

@test "check mode: clean tree exits 0 silently" {
  seed_tree
  bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'" >/dev/null
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh' check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no project skills dir and no .gitignore — plugin skills still copy, no .gitignore created" {
  run bash -c "cd '$TMP' && '$SCRIPTS/link-agent-skills.sh'"
  [ "$status" -eq 0 ]
  [ -d "$TMP/.agents/skills/test-driven-development" ]
  [ ! -e "$TMP/.gitignore" ]
}
```

- [ ] `bats tests/link-agent-skills.bats` — verify the new expectations FAIL
      against the old script.
- [ ] Rewrite `plugin/scripts/link-agent-skills.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Copy skills codex must see into ./.agents/skills as committed files (codex
# scans cwd → repo root). Sources win; unrecognized dirs are never touched.
# Usage: link-agent-skills.sh [check]   — check prints DRIFT lines, exits 1.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SKILLS="$(cd "$HERE/../skills" && pwd)"
PLUGIN_LIST=(test-driven-development systematic-debugging gotchas)

ROOT="$PWD"
DEST="$ROOT/.agents/skills"
MODE="${1:-apply}"
drift=0

sync_one() { # $1=src dir $2=name
  local src="$1" name="$2"
  local tgt="$DEST/$name"
  if [[ ! -L "$tgt" && -d "$tgt" ]] && diff -rq "$src" "$tgt" >/dev/null 2>&1; then return; fi
  if [[ "$MODE" == check ]]; then
    echo "DRIFT: .agents/skills/$name missing or stale — fix: link-agent-skills.sh"
    drift=$((drift + 1)); return
  fi
  mkdir -p "$DEST"
  rm -rf "$tgt"
  cp -R "$src" "$tgt"
  echo "synced .agents/skills/$name"
}

for s in "${PLUGIN_LIST[@]}"; do
  sync_one "$PLUGIN_SKILLS/$s" "$s"
done
for d in "$ROOT/.claude/skills"/*/; do
  [[ -d "$d" ]] || continue
  sync_one "${d%/}" "$(basename "$d")"
done

# migration off the old symlink design: copies are committed, never ignored
if grep -qxF '.agents/' "$ROOT/.gitignore" 2>/dev/null; then
  if [[ "$MODE" == check ]]; then
    echo "DRIFT: .agents/ still gitignored — fix: link-agent-skills.sh"
    drift=$((drift + 1))
  else
    tmp="$(mktemp)"
    grep -vxF '.agents/' "$ROOT/.gitignore" > "$tmp" || true
    mv "$tmp" "$ROOT/.gitignore"
    echo "removed .agents/ from .gitignore"
  fi
fi

[[ "$drift" -eq 0 ]] || exit 1
```

- [ ] `bats tests/link-agent-skills.bats` — PASS; `shellcheck
      plugin/scripts/*.sh` — clean.
- [ ] Commit: `feat(skills): link-agent-skills copies committed skills, drops gitignore (#91)`

## Task 2 — repo migration + docs + bump

Files: `.agents/skills/*`, `.gitignore`, `plugin/skills/doctor/SKILL.md`,
`plugin/skills/executing-tasks/SKILL.md`, `docs/DECISIONS.md`,
`plugin/.claude-plugin/plugin.json`. TDD n/a: migration + prose; verification
= full suite + a real run of the new script.

- [ ] From the worktree root run `plugin/scripts/link-agent-skills.sh` (the
      WORKTREE copy — sources = this repo's plugin dir). Verify: real dirs in
      `.agents/skills/`, `.agents/` gone from `.gitignore`,
      `git status` shows them as addable.
- [ ] `plugin/skills/doctor/SKILL.md`: replace the linker bullet — check
      prints DRIFT → run apply without asking; resulting changes are
      ordinary dirty files that ride with the next branch/PR (pluginVersion
      stamp convention); codex can't see TDD/project skills until synced.
- [ ] `plugin/skills/executing-tasks/SKILL.md`: delete the "first run
      link-agent-skills.sh from the worktree root …" sentence (committed
      copies exist in every worktree); keep the rest of the codex-lane step.
- [ ] `docs/DECISIONS.md`: append under a `## 2026-07-16 — Agent skills are
      committed copies` heading: copy-and-commit replaces symlink+gitignore;
      `.agents/skills/` is contributor-committable; sources (plugin dir,
      `.claude/skills`) win; per-worktree relink step retired.
- [ ] `plugin/.claude-plugin/plugin.json`: patch bump per the global
      constraint (rebase on main first, then current+1).
- [ ] Full suite: `bats tests` + the shellcheck line — green, real counts.
- [ ] Commit: `feat(skills): commit .agents/skills copies, migrate repo, retire relink step (#91)`

## Self-review

- Spec → tasks: copy semantics+check+migration line (T1), never-touch rule
  (T1 test), docs trio + repo migration + bump (T2). Covered.
- `sync_one` name consistent; DRIFT wording matches doctor SKILL.md text.
- Version-bump conflict with PR #93 handled by rebase-then-bump constraint.
- Single PR → straight to execution.
