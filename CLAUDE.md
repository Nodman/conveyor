<!-- conveyor:begin -->
## Conveyor workflow

This repo uses the **conveyor** plugin. Task state lives on the GitHub Projects
board (Nodman/6); ids in `.claude/conveyor.json` — never hardcode them.

- Work requests → `/conveyor:work` (or brainstorm first for new features).
- Lifecycle: Ready for dev → In Progress → PR (`Fixes #n`) → Agent Review →
  QA → human merge → Done (automation). Human-blocked cards → Human Only with
  an `**Unblock:**` comment.
- Docs: specs → `docs/specs/`, plans → `docs/plans/`, rulings →
  `docs/DECISIONS.md`, traps → `docs/gotchas/` (via the gotchas skill).
- History = squash-commit bodies (≤6-bullet PR summaries). No status/changelog docs.
- Board drift? Run `/conveyor:doctor`.
<!-- conveyor:end -->
