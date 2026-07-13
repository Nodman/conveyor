#!/usr/bin/env bash
set -euo pipefail
# Link skills codex must see into ./.agents/skills (codex scans cwd → repo root;
# a worktree is its own root, so run this from each root codex works in).
# Usage: link-agent-skills.sh [check]   — check prints DRIFT lines, exits 1.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_SKILLS="$(cd "$HERE/../skills" && pwd)"
PLUGIN_LIST=(test-driven-development systematic-debugging gotchas)

ROOT="$PWD"
DEST="$ROOT/.agents/skills"
MODE="${1:-apply}"
drift=0

link_one() { # $1=src dir $2=name
  local src="$1" name="$2"
  local tgt="$DEST/$name"
  if [[ -L "$tgt" && "$(readlink "$tgt")" == "$src" ]]; then return; fi
  if [[ "$MODE" == check ]]; then
    echo "DRIFT: .agents/skills/$name missing or stale — fix: link-agent-skills.sh"
    drift=$((drift + 1)); return
  fi
  mkdir -p "$DEST"
  ln -sfn "$src" "$tgt"
  echo "linked .agents/skills/$name -> $src"
}

for s in "${PLUGIN_LIST[@]}"; do
  link_one "$PLUGIN_SKILLS/$s" "$s"
done
for d in "$ROOT/.claude/skills"/*/; do
  [[ -d "$d" ]] || continue
  link_one "${d%/}" "$(basename "$d")"
done

# symlink targets are machine-specific plugin-cache paths — never commit them
if ! grep -qxF '.agents/' "$ROOT/.gitignore" 2>/dev/null; then
  if [[ "$MODE" == check ]]; then
    echo "DRIFT: .agents/ not gitignored — fix: link-agent-skills.sh"
    drift=$((drift + 1))
  else
    echo '.agents/' >> "$ROOT/.gitignore"
    echo "added .agents/ to .gitignore"
  fi
fi

[[ "$drift" -eq 0 ]] || exit 1
