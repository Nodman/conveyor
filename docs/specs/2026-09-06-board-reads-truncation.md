# Board reads: remove the 200-item truncation

## What

Replace all capped `gh project item-list --limit 200` board reads with three
GraphQL readers that work at any board size:

- **per-issue lookup** — `card.sh find/move`
- **filtered queue** — work/auto card picking
- **full paginated scan** — board-doctor

## Why

- `item-list` returns oldest-first; on Nodman/fin-app (267 items) the newest
  ~70 cards are invisible: `card.sh` exits 3 ("no card"), lifecycle moves
  silently fail, work/auto can't see new Ready cards, doctor skips them.
- Only signal today is a stderr WARN (`warn_capped`), and `count == limit`
  is a guess; `item-list` also flakes on 200+ boards (cli/cli#13432).
- User constraint: boards may pass 1000 items; archiving Done cards is NOT
  assumed.

## Verified facts (2026-09-06, live API)

- `issue(number:N){projectItems(first:100, includeArchived:false){nodes{id
  project{number} fieldValueByName(name:"Status"){...}}}}` — 0.5s, O(1) in
  board size.
- `items(query:"is:issue is:open status:\"Ready for dev\"")` — server-side
  filter works (shipped Nov 2025); `status:"Human Only"` returned exactly 13.
- `gh api graphql --paginate` + `items(first:100, after:$endCursor)` +
  `--slurp` — all 267 items in 3.3s; linear (~10s per 1000). `totalCount`
  present; archived items excluded from the connection.

## Decisions (locked)

- Drop `gh project item-list` from all board reads; no arbitrary `--limit`
  anywhere in the board path.
- New `plugin/scripts/board-items.sh` with subcommands; skills call it
  instead of embedding gh prose:
  - `find <issue>` / consumed by `card.sh` — per-issue lookup, match
    `project.number == cfg .project`; exit 3 only on confirmed absence;
    API/GraphQL errors stay hard failures (non-3).
  - `queue <statusKey>` — server-side filtered, paginated; emits
    TSV `number<TAB>priority<TAB>title`, sorted number ascending (issue
    numbers are creation-ordered → "ties oldest" = lowest number first;
    priority sort stays in the caller).
  - `scan` — full-board cursor pagination; hard-fail unless fetched node
    count (ALL items: issues, PRs, drafts) == `totalCount`, checked before
    any filtering. Then emits issue rows only, one JSON object per line:
    `{"number": N, "status": "...", "state": "OPEN|CLOSED"}` (`state`
    inline from the issue content — replaces doctor's `gh issue list`).
- `board-doctor.sh` uses `scan`; drop the separate
  `gh issue list --limit 300` (state comes inline).
- `card.sh` keeps its CLI (`find|move ISSUE [STATUS_KEY]`) — only the read
  path changes.
- work/auto SKILL.md: picking step becomes `board-items.sh queue ready`
  (priority sort P1>P2>P3, unset=P2, ties oldest — unchanged, done locally).
- Remove `warn_capped` calls on board reads; keep helper for remaining
  capped calls (`gh label list`).
- GPT-5.6-sol consulted (2026-09-06): concurs; rejected `first:10`
  projectItems (hidden cap → use 100), rejected issue-side inversion for
  queue.

## Error handling

- GraphQL partial errors / empty `data` → die, never "no card".
- Pagination must terminate on `hasNextPage:false`; mismatch vs `totalCount`
  → die with counts in message.
- Eventual consistency unchanged (docs/gotchas/github-api.md): no
  read-after-write assertions added.

## Testing

- bats, existing gh stub (named-operation `graphql_*.out` fixtures):
  - find: hit, miss (exit 3), API error (hard fail)
  - queue: filter arg contains status name; multi-page merge
  - scan: fetched != totalCount dies; doctor green path on fixture board
- Update card.bats: 200-cap WARN test replaced by API-error test.
- Version bump `plugin/.claude-plugin/plugin.json` (touches `plugin/`).

## Out of scope

- Archiving policy / auto-archive workflows.
- Concurrency (compare-and-set moves, double-pick serialization).
- Retry/backoff machinery.
