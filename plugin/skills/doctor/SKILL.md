---
name: doctor
description: Run at the START of any conveyor activity in a session (work, auto, brainstorming, council, executing-tasks) — and again when a board card looks wrong or after config/board changes. Runs the drift script and session-level checks; proposes fixes.
---

# /conveyor:doctor

Session gate: run once before the first conveyor activity of a session;
re-run only when something looks wrong.

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/board-doctor.sh` from the repo root.
2. Session-level checks the script can't do:
   - superpowers skills present in your available-skills list → flag (conveyor
     replaces it). Fix: `claude plugin disable <id> --scope project` — use the
     plugin id from the session's skill list (e.g.
     `superpowers@claude-plugins-official`); it writes the override to project
     `.claude/settings.json`. Ask the user first, never write settings
     silently; takes effect next session.
   - `.claude/skills/running-the-app` / `running-tests` missing or still
     containing `<!-- FILL -->` → flag (QA is blocked without them).
   - `.claude/settings.json` permissions.allow missing any of
     `Bash(gh pr edit:*)`, `Bash(gh issue edit:*)`,
     `Bash(gh issue comment:*)`, `Bash(gh issue create:*)` → flag (agents
     cannot apply lifecycle labels, comment on issues, or file backlog
     issues). Fix: `scaffold.sh --grant-label-perms` — ask the user first,
     never write permissions silently.
   - `link-agent-skills.sh check` prints DRIFT → run
     `${CLAUDE_PLUGIN_ROOT}/scripts/link-agent-skills.sh` without asking
     (local symlinks in a gitignored dir). Codex can't see the TDD or
     project skills until they're linked into `.agents/skills/`.
   - `codex-exec.sh detect` prints `unset` → flag: council/external agents
     will interrupt to ask on first use. Fix: `codex-exec.sh set-visibility
     <window|background>` — ask the user which, never write config silently.
   - `codex-exec.sh preflight` fails while `plugin/skills/routing/` ships codex
     pool rows → note codex lanes dormant (install + auth codex to enable);
     preflight passes but an earlier doctor run flagged dormancy → note codex
     lanes now active.
   - `gh api repos/{owner}/{repo}/branches/main/protection` returns 404 → WARN:
     `main` lacks branch protection (agents and humans can direct/force-push).
     Fix: enable branch protection on `main` (repo settings, or `gh api
     --method PUT …/branches/main/protection`). Warn-only — report and move on,
     never blocks.
3. Report findings as bullets with the concrete fix for each (the exact
   `card.sh move`, label, or comment command). Ask before fixing anything
   that changes board state; never move a card to Done (automation only).
   If the script printed `stamped pluginVersion … — commit .claude/conveyor.json`,
   run `git commit -m "chore: doctor — stamp pluginVersion <new>" .claude/conveyor.json`.
   No ask is needed; this shares the installed version with other clones.
   No findings → say "no drift" and stop.
