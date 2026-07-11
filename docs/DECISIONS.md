# Decisions

Each entry: `## YYYY-MM-DD — <topic>` followed by bullets — chose X over Y, because…

## 2026-07-11 — Lifecycle hygiene rulings

- Label permissions: granted only via `scaffold.sh --grant-label-perms` after
  an explicit user yes — consent gate over silent settings writes.
- Human-required follow-ups: hybrid — merge-time actions → one
  `**Human required:**` PR comment; scope/credential or PR-outliving work →
  Human Only card with `**Unblock:**`. Chosen over cards-for-everything to
  keep the board signal high.
- Every agent-authored PR/issue comment carries a `**[<agent-name>]**` prefix.
- Plugin PRs bump the `plugin.json` patch version; consumers pull via
  `claude plugin marketplace update` + `claude plugin update`.
