#!/usr/bin/env bash
set -euo pipefail
# Copy skills codex must see into ./.agents/skills as committed files (codex
# scans cwd → repo root). Sources win; unrecognized dirs are never touched.
# Usage: link-agent-skills.sh [check]   — check prints DRIFT lines, exits 1.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SKILLS="$(cd "$HERE/../skills" && pwd)"
PLUGIN_LIST=(test-driven-development systematic-debugging gotchas worktrees)

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
