---
name: init
description: Use to install the conveyor workflow into the current repository — board create/adopt, config, scaffolding, project-skill stubs. Interactive; safe to re-run.
---

# /conveyor:init

Scripts live in `${CLAUDE_PLUGIN_ROOT}/scripts/`. Ask before every mutating
step on a repo that already has related state.

1. **Preflight.** `gh auth status` ok; `project` scope present (else tell the
   user: `gh auth refresh -s project`); a GitHub remote exists; `jq`
   installed. If the superpowers plugin is active in this session (its skills
   appear in your available-skills list), WARN: conveyor replaces it —
   ask the user to disable it for this project before continuing.
2. **Board.** `board-discover.sh --find OWNER REPO`:
   - No project → confirm, then `board-create.sh OWNER REPO "<repo name>"`.
   - Project found → `board-discover.sh OWNER N`, show its columns, and ask
     the user (AskUserQuestion, one canonical state at a time, only for
     unmatched ones) which existing column maps to each canonical state; then
     `board-reconcile.sh OWNER N <mapping.json>`. The mapping file is a JSON
     object of canonical key → EXISTING column name, e.g.
     `{"backlog": "Todo", "done": "Done"}`; unmapped canonical states get
     created. Renames preserve item values (matched by option id). After the
     status mapping, reconcile also creates the canonical Priority field
     (P1/P2/P3) if the board has none.
3. **Manual checklist.** Print — the API cannot set these; the user does them
   in the board UI once: enable "Item added to project → Backlog"; enable
   "Item closed → Done"; ensure "Pull request linked → …" workflows stay
   DISABLED (re-enabling re-moves merged cards). Ask the user to confirm done.
4. **Config.** Re-run `board-discover.sh` post-reconcile; write
   `.claude/conveyor.json` (schema in the plugin README; mergePolicy: ask
   solo vs maintainers). Verify every status and priority key has an id.
   Include `"pluginVersion"`: the installed plugin's version
   (`jq -r .version ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`) — the
   session-start hook compares it to nudge `/conveyor:doctor` after updates.
5. **Scaffold.** `scaffold.sh` (docs dirs, issue template, labels, CLAUDE.md
   block). Show the diff to the user.
6. **Label permissions (consent gate).** Conveyor agents apply lifecycle
   labels (`gh pr edit --add-label`); permission classifiers may block that.
   Show the user the exact rules — `Bash(gh pr edit:*)`,
   `Bash(gh issue edit:*)` — the file (`.claude/settings.json`, checked in),
   and why. AskUserQuestion: grant / skip. Yes →
   `scaffold.sh --grant-label-perms`; no → labels stay a manual human step at
   merge time. Never write permissions without this explicit yes.
7. **Conflict scan.** Read the repo's CLAUDE.md/AGENTS.md fully. Report (do
   NOT edit): competing lifecycle/board instructions, superpowers references,
   rules contradicting the conveyor lifecycle (e.g. "commit to main"). The
   user reconciles their own prose.
8. **Project skills.** Inspect the stack (build files, CI, README). Generate
   `.claude/skills/running-the-app/SKILL.md` and
   `.claude/skills/running-tests/SKILL.md` from the plugin templates, filling
   what you can determine (exact commands); leave `<!-- FILL -->` markers
   where you cannot. Ask the user to review — these are what qa-agent and
   executors depend on.
9. **Verify.** Run `/conveyor:doctor`. Commit the scaffolding on a branch and
   offer a PR.
