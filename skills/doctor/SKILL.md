---
name: doctor
description: Use at task pickup, when a board card looks wrong, or after config/board changes. Runs the drift script and session-level checks; proposes fixes.
---

# /conveyor:doctor

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/board-doctor.sh` from the repo root.
2. Session-level checks the script can't do:
   - superpowers skills present in your available-skills list → flag (conveyor
     replaces it; user should disable it for this project).
   - `.claude/skills/running-the-app` / `running-tests` missing or still
     containing `<!-- FILL -->` → flag (QA is blocked without them).
3. Report findings as bullets with the concrete fix for each (the exact
   `card.sh move`, label, or comment command). Ask before fixing anything
   that changes board state; never move a card to Done (automation only).
   No findings → say "no drift" and stop.
