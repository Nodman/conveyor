#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

if [[ "${1:-}" == "--find" ]]; then
  owner="$2"; repo="$3"
  num=$(gh project list --owner "$owner" --format json \
    | jq -r --arg r "$repo" '[.projects[] | select(.title==$r)][0].number // empty')
  [[ -n "$num" ]] || die_code3 "no project linked to $repo"
  echo "$num"; exit 0
fi

owner="$1"; number="$2"
pid=$(gh project view "$number" --owner "$owner" --format json | jq -r '.id')
fields=$(gh project field-list "$number" --owner "$owner" --format json)
canon_status='{"humanOnly":"Human Only","backlog":"Backlog","ready":"Ready for dev","inProgress":"In Progress","agentReview":"Agent Review","qa":"QA","done":"Done","archived":"Archived"}'
canon_prio='{"p1":"P1","p2":"P2","p3":"P3"}'

jq -n --arg pid "$pid" --argjson f "$fields" --argjson cs "$canon_status" --argjson cp "$canon_prio" '
  def opts(fname): ([$f.fields[] | select(.name==fname)][0]) as $fld
    | {id: ($fld.id // null),
       map: (reduce ($fld.options // [])[] as $o ({}; .[$o.name] = $o.id))};
  (opts("Status")) as $s | (opts("Priority")) as $p |
  { projectId: $pid,
    statusFieldId: $s.id,
    status: ($cs | with_entries(.value as $n | .value =
      (if $s.map[$n] then {name:$n, id:$s.map[$n]} else null end))),
    priorityFieldId: $p.id,
    priority: (if $p.id then ($cp | with_entries(.value as $n | .value =
      (if $p.map[$n] then {name:$n, id:$p.map[$n]} else null end))) else null end) }'
