#!/usr/bin/env bash
set -euo pipefail
# PreToolUse hook: remind that CLAUDE.md / AGENTS.md are durable rules only.
# Malformed stdin → jq fails → empty path → no output (guarded).

input="$(cat || true)"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

if [[ "$path" =~ (CLAUDE|AGENTS)\.md$ ]]; then
  read -r -d '' reminder <<'EOF' || true
Reminder: CLAUDE.md / AGENTS.md are durable rules + pointers ONLY. Do NOT add status, what-landed, dates, issue numbers, or done-markers here. Route what-landed to the PR body (it becomes the squash commit), traps to docs/gotchas/ (gotchas skill), architecture rulings to docs/DECISIONS.md.
EOF
  jq -n --arg ctx "$reminder" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
fi

exit 0
