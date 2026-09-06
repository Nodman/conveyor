#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

cmd="${1:-}"

no_gql_errors() { # $1=response json (object or slurp array) $2=op — die on partial .errors
  if jq -e 'if type=="array" then any(.[]; .errors != null) else .errors != null end' \
      <<<"$1" >/dev/null 2>&1; then
    die "$2: GraphQL errors in response"
  fi
}

find_item() { # $1=issue → "itemId<TAB>status" | exit 3 absent | die on failure
  local raw row
  raw=$(gh api graphql \
    -f query='query CardItem($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){projectItems(first:100,includeArchived:false){nodes{id project{number} fieldValueByName(name:"Status"){... on ProjectV2ItemFieldSingleSelectValue{name}}}}}}}' \
    -f o="$(cfg .owner)" -f r="$(cfg .repo)" -F n="$1") || die "CardItem query failed"
  no_gql_errors "$raw" CardItem
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
