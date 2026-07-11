#!/usr/bin/env bash
set -euo pipefail
# SessionStart hook: inject Conveyor working principles into human sessions.
# Never re-inject into subagents (lesson from the superpowers hook).

input="$(cat || true)"

case "$input" in
  *'"agent_type"'*) printf '{}'; exit 0 ;;
esac

read -r -d '' text <<'EOF' || true
Conveyor working principles:
1. Think before coding — state assumptions; multiple interpretations → ask, don't pick silently. Push back when a simpler approach exists.
2. Simplicity first — minimum code that solves the problem; nothing speculative.
3. Surgical changes — every changed line traces to the request; match existing style.
4. Goal-driven — turn tasks into verifiable goals; loop until verified.

Process gate: a human work request starts with /conveyor:brainstorming (scale it to the task — a trivial fix needs one question, not twenty). Never implement before an approved spec for feature-sized work.

If .claude/conveyor.json exists: this repo runs the conveyor board lifecycle — see the Conveyor section of CLAUDE.md; /conveyor:work to pick up tasks, /conveyor:doctor when a card looks wrong.
EOF

if [[ -f .claude/conveyor.json ]]; then
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  installed="$(jq -r '.version // empty' "$here/../.claude-plugin/plugin.json" 2>/dev/null || true)"
  stamped="$(jq -r '.pluginVersion // empty' .claude/conveyor.json 2>/dev/null || true)"
  if [[ -n "$installed" && "$stamped" != "$installed" ]]; then
    text+=$'\n\n'"conveyor plugin updated ${stamped:-unstamped} → $installed since this repo was configured — run /conveyor:doctor to reconcile."
  fi
fi

jq -n --arg ctx "$text" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
