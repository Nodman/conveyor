# Plan: board reads without 200-item truncation

Spec: docs/specs/2026-09-06-board-reads-truncation.md · Issue: #103 · Single PR.

**Goal:** every board read works at any board size; no `gh project item-list` in read paths.

**Architecture:** new `plugin/scripts/board-items.sh` owns all board reads as three GraphQL
readers — `find` (per-issue, O(1)), `queue` (server-side `items(query:)` filter),
`scan` (cursor pagination + totalCount check). `card.sh` and `board-doctor.sh` consume it;
work/auto skills call `queue ready`.

**Global constraints:**
- GraphQL ops named `CardItem`, `QueueItems`, `ScanItems` (gh test stub matches `query <Op>(`).
- Page size 100 everywhere; `--paginate --slurp` for multi-page (fixtures = slurp arrays).
- Errors: exit 3 ONLY for confirmed card absence; anything else dies exit 1.
- Bats gotchas (docs/gotchas/bats.md): mid-test asserts use `[ ]`; decisive assert last.
- Test config: owner=acme repo=widget project=7 projectId=PVT_kwTEST.

## File map

| file | responsibility |
|---|---|
| plugin/scripts/board-items.sh | new: find / queue / scan readers |
| tests/board-items.bats | new: tests for all three |
| tests/fixtures/card/graphql_CardItem.out | new fixture: hit |
| tests/fixtures/card-miss/graphql_CardItem.out | new fixture: no card in project 7 |
| tests/fixtures/board-items/* | queue/scan fixtures |
| plugin/scripts/card.sh | read path → board-items.sh find |
| tests/card.bats | drop item-list fixtures/WARN test; add hard-fail test |
| plugin/scripts/board-doctor.sh | items via scan; drop `gh issue list` + warn_capped |
| tests/fixtures/doctor-*/graphql_ScanItems.out | converted from project_item-list.out+issue_list.out |
| plugin/skills/work/SKILL.md, plugin/skills/auto/SKILL.md | pick step → queue ready |
| plugin/.claude-plugin/plugin.json | 0.1.38 → 0.1.39 |

## Task 1 — board-items.sh find + card.sh delegation

Files: plugin/scripts/board-items.sh (new), plugin/scripts/card.sh, tests/board-items.bats
(new), tests/card.bats, fixtures card/ + card-miss/.

Interfaces produced: `board-items.sh find <issue>` → stdout `itemId<TAB>statusName`,
exit 0; exit 3 confirmed absence; exit 1 API/GraphQL failure. `card.sh` CLI unchanged.

- [ ] Failing tests. `tests/fixtures/card/graphql_CardItem.out`:
```json
{"data":{"repository":{"issue":{"projectItems":{"nodes":[
  {"id":"PVTI_99","project":{"number":42},"fieldValueByName":{"name":"Done"}},
  {"id":"PVTI_41","project":{"number":7},"fieldValueByName":{"name":"Ready for dev"}}
]}}}}}
```
  `tests/fixtures/card-miss/graphql_CardItem.out`: same shape, only the project-42 node.
  Delete `tests/fixtures/card/project_item-list.out`.
  `tests/board-items.bats` (same header/`use_cfg` as card.bats):
```bash
@test "find prints item id and status, ignores other projects" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 0 ]
  [ "$output" = $'PVTI_41\tReady for dev' ]
}
@test "find exits 3 when no item belongs to this project" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/card-miss" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 3 ]
}
@test "find dies non-3 on API failure" {
  use_cfg
  mkdir -p "$TMP/nofix"
  GH_FIX="$TMP/nofix" run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' find 41"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CardItem query failed"* ]]
}
```
  In `tests/card.bats`: keep find/move/usage tests as-is (fixtures now serve them via
  card/graphql_CardItem.out); "find exits 3 when no card exists" switches to
  `GH_FIX=.../fixtures/card-miss` with `find 99`; REPLACE the 200-cap WARN test with:
```bash
@test "find hard-fails (not exit 3) when the board read errors" {
  use_cfg
  mkdir -p "$TMP/nofix"
  GH_FIX="$TMP/nofix" run bash -c "cd '$TMP' && '$SCRIPTS/card.sh' find 41"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CardItem query failed"* ]]
}
```
- [ ] Run `bats tests/board-items.bats tests/card.bats` — new tests fail (no script / old read path).
- [ ] Implement `plugin/scripts/board-items.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

cmd="${1:-}"

find_item() { # $1=issue → "itemId<TAB>status" | exit 3 absent | die on failure
  local raw row
  raw=$(gh api graphql \
    -f query='query CardItem($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){projectItems(first:100,includeArchived:false){nodes{id project{number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
    -f o="$(cfg .owner)" -f r="$(cfg .repo)" -F n="$1") || die "CardItem query failed"
  jq -e '.data.repository.issue.projectItems.nodes' <<<"$raw" >/dev/null 2>&1 \
    || die "CardItem: no data for issue #$1 (missing issue or API error)"
  row=$(jq -r --argjson p "$(cfg .project)" \
    '[.data.repository.issue.projectItems.nodes[] | select(.project.number==$p)][0] // empty
     | "\(.id)\t\(.fieldValueByName.name // "")"' <<<"$raw")
  [[ -n "$row" ]] || die_code3 "no card for issue #$1"
  printf '%s\n' "$row"
}

case "$cmd" in
  find)  [[ -n "${2:-}" ]] || die "usage: board-items.sh find ISSUE"; find_item "$2" ;;
  *) die "usage: board-items.sh find|queue|scan ..." ;;
esac
```
  `card.sh`: delete `item_row()` and its `warn_capped`; replace `row="$(item_row)"` +
  empty-check with:
```bash
row="$("$(dirname "${BASH_SOURCE[0]}")/board-items.sh" find "$issue")"
```
  (set -e propagates exit 3 / exit 1 with board-items' message; drop the old
  `[[ -n "$row" ]] || die_code3` line).
- [ ] `bats tests/board-items.bats tests/card.bats` green; full suite green.
- [ ] Commit: `board-items.sh find: per-issue card lookup replaces item-list in card.sh (#103)`

## Task 2 — queue

Files: board-items.sh, tests/board-items.bats, tests/fixtures/board-items/graphql_QueueItems.out.

Interface produced: `board-items.sh queue <statusKey>` → TSV `number<TAB>priority<TAB>title`,
number-ascending; priority empty when unset.

- [ ] Failing tests. Fixture (slurp array, two pages, unordered, one unset priority):
```json
[{"data":{"node":{"items":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
  {"content":{"number":30,"title":"thirty"},"priority":{"name":"P2"}},
  {"content":{"number":12,"title":"twelve"},"priority":{"name":"P1"}}]}}}},
 {"data":{"node":{"items":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"content":{"number":25,"title":"twenty five"},"priority":null}]}}}}]
```
```bash
@test "queue emits number-ascending TSV across pages, empty priority for unset" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 0 ]
  [ "$output" = $'12\tP1\ttwelve\n25\t\ttwenty five\n30\tP2\tthirty' ]
}
@test "queue passes the status name in the server-side filter" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 0 ]
  run grep -F 'status:"Ready for dev"' "$GH_LOG"
  [ "$status" -eq 0 ]
}
@test "queue dies on API failure" {
  use_cfg
  mkdir -p "$TMP/nofix"
  GH_FIX="$TMP/nofix" run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' queue ready"
  [ "$status" -eq 1 ]
  [[ "$output" == *"QueueItems query failed"* ]]
}
```
- [ ] Run — fail (unknown subcommand).
- [ ] Implement in board-items.sh (+ `queue` case arm):
```bash
queue_items() { # $1=statusKey → TSV number<TAB>priority<TAB>title, number-ascending
  local q raw
  q="is:issue is:open status:\"$(status_name "$1")\""
  raw=$(gh api graphql --paginate --slurp \
    -f query='query QueueItems($pid:ID!,$q:String!,$endCursor:String){node(id:$pid){... on ProjectV2{items(query:$q,first:100,after:$endCursor){pageInfo{hasNextPage endCursor} nodes{content{... on Issue{number title}} priority:fieldValueByName(name:"Priority"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
    -f pid="$(cfg .projectId)" -f q="$q") || die "QueueItems query failed"
  jq -e 'all(.[]; .data.node.items.nodes != null)' <<<"$raw" >/dev/null 2>&1 \
    || die "QueueItems: bad response"
  jq -r '[.[].data.node.items.nodes[] | select(.content.number != null)]
         | sort_by(.content.number)[]
         | "\(.content.number)\t\(.priority.name // "")\t\(.content.title)"' <<<"$raw"
}
```
- [ ] Green; full suite green.
- [ ] Commit: `board-items.sh queue: server-side status filter for card picking (#103)`

## Task 3 — scan

Files: board-items.sh, tests/board-items.bats, fixtures board-items/scan-ok/ + scan-mismatch/
(each holding graphql_ScanItems.out).

Interface produced: `board-items.sh scan` → JSON lines
`{"number":N,"status":"...","state":"OPEN|CLOSED"}` (issues only); dies unless
all-item fetched count == totalCount.

- [ ] Failing tests. scan-ok fixture (2 pages; 4 items incl. one DraftIssue; totalCount 4):
```json
[{"data":{"node":{"items":{"totalCount":4,"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
  {"content":{"__typename":"Issue","number":10,"state":"OPEN"},"status":{"name":"Ready for dev"}},
  {"content":{"__typename":"DraftIssue"},"status":{"name":"Backlog"}}]}}}},
 {"data":{"node":{"items":{"totalCount":4,"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
  {"content":{"__typename":"Issue","number":11,"state":"CLOSED"},"status":{"name":"Done"}},
  {"content":{"__typename":"Issue","number":12,"state":"OPEN"},"status":null}]}}}}]
```
  scan-mismatch: same but `totalCount":6`.
```bash
@test "scan emits issue JSON lines, skips drafts, keeps null status" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items/scan-ok" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' scan"
  [ "$status" -eq 0 ]
  [ "$output" = '{"number":10,"status":"Ready for dev","state":"OPEN"}
{"number":11,"status":"Done","state":"CLOSED"}
{"number":12,"status":"","state":"OPEN"}' ]
}
@test "scan dies when fetched count != totalCount" {
  use_cfg
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/board-items/scan-mismatch" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-items.sh' scan"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fetched 4 != totalCount 6"* ]]
}
```
- [ ] Run — fail.
- [ ] Implement (+ `scan` case arm):
```bash
scan_items() { # → JSON lines {"number","status","state"}; dies on count mismatch
  local raw total fetched
  raw=$(gh api graphql --paginate --slurp \
    -f query='query ScanItems($pid:ID!,$endCursor:String){node(id:$pid){... on ProjectV2{items(first:100,after:$endCursor){totalCount pageInfo{hasNextPage endCursor} nodes{content{__typename ... on Issue{number state}} status:fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
    -f pid="$(cfg .projectId)") || die "ScanItems query failed"
  total=$(jq -er '.[0].data.node.items.totalCount' <<<"$raw") || die "ScanItems: bad response"
  fetched=$(jq -r '[.[].data.node.items.nodes | length] | add' <<<"$raw")
  [[ "$fetched" -eq "$total" ]] || die "ScanItems: fetched $fetched != totalCount $total"
  jq -c '.[].data.node.items.nodes[] | select(.content.__typename=="Issue")
         | {number:.content.number, status:(.status.name // ""), state:.content.state}' <<<"$raw"
}
```
- [ ] Green; full suite green.
- [ ] Commit: `board-items.sh scan: paginated full-board read with totalCount check (#103)`

## Task 4 — doctor on scan

Files: plugin/scripts/board-doctor.sh, tests/fixtures/doctor-*/. board-doctor.bats
assertions stay UNCHANGED — only fixtures and the doctor read path move.

- [ ] Convert fixtures (one-off, run from repo root, then delete originals):
```bash
for d in tests/fixtures/doctor-*; do
  [ -f "$d/project_item-list.out" ] || continue
  open=$(cat "$d/issue_list.out" 2>/dev/null || echo '[]')
  jq --argjson open "$open" '
    [{data:{node:{items:{
      totalCount:(.items|length),
      pageInfo:{hasNextPage:false,endCursor:null},
      nodes:[.items[] | {
        content:{__typename:(.content.type // "Issue"), number:.content.number,
                 state:(if ([$open[].number]|index(.content.number)) then "OPEN" else "CLOSED" end)},
        status:{name:.status}}]}}}}]' \
    "$d/project_item-list.out" > "$d/graphql_ScanItems.out"
  rm -f "$d/project_item-list.out" "$d/issue_list.out"
done
```
- [ ] Run `bats tests/board-doctor.bats` — fails (doctor still calls item-list, no fixture).
- [ ] Edit board-doctor.sh: replace the items_raw/warn_capped/items/open_raw/openset block with:
```bash
scan_out=$("$HERE/board-items.sh" scan)
items=$(jq -sc 'map({n:.number, status:.status, state:.state})' <<<"$scan_out")
```
  Loop header becomes `while IFS=$'\t' read -r n status state; do`, the
  `isopen=$(jq -n ...)` line becomes `isopen=$([[ "$state" == OPEN ]] && echo true || echo false)`,
  and the feeder becomes `done < <(jq -r '.[] | "\(.n)\t\(.status)\t\(.state)"' <<<"$items")`.
  Non-issue filtering already happened in scan.
- [ ] `bats tests/board-doctor.bats` green; full suite green.
- [ ] Commit: `board-doctor: read board via board-items.sh scan; drop issue-list cap (#103)`

## Task 5 — skills prose, leftovers, version

Files: plugin/skills/work/SKILL.md, plugin/skills/auto/SKILL.md,
plugin/.claude-plugin/plugin.json. TDD n/a (prose/config) — verification steps instead.

- [ ] work/SKILL.md step 2 and auto/SKILL.md step 3, pick sentence becomes:
  ``Pick: `${CLAUDE_PLUGIN_ROOT}/scripts/board-items.sh queue ready` → TSV
  `number<TAB>priority<TAB>title`, number-ascending → highest Priority first
  (P1 > P2 > P3; unset = P2); ties → first row (lowest number = oldest).``
- [ ] Verify no read-path leftovers: `grep -rn 'item-list' plugin/` → only
  board-reconcile's `field-list` (different command) may remain; zero `gh project item-list`.
  `warn_capped` helper stays in lib.sh; zero remaining callers is acceptable.
- [ ] Bump plugin.json version 0.1.38 → 0.1.39.
- [ ] Full suite green (`bats tests/`); shellcheck board-items.sh, card.sh, board-doctor.sh.
- [ ] Commit: `skills: pick cards via board-items.sh queue; bump 0.1.39 (#103)`

## Board mapping

Single PR (`Fixes #103`) from all five task commits, branch in a `.worktrees/` worktree
per conveyor:worktrees.
