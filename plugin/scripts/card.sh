#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

cmd="${1:-}"; issue="${2:-}"
[[ "$cmd" == "find" || "$cmd" == "move" ]] || die "usage: card.sh find|move ISSUE [STATUS_KEY]"
[[ -n "$issue" ]] || die "usage: card.sh find|move ISSUE [STATUS_KEY]"

item_row() {
  gh project item-list "$(cfg .project)" --owner "$(cfg .owner)" --limit 200 --format json \
    | jq -r --argjson n "$issue" \
      '.items[] | select(.content.number==$n) | "\(.id)\t\(.status // "")"' | head -1
}

row="$(item_row)"
[[ -n "$row" ]] || die_code3 "no card for issue #$issue"

case "$cmd" in
  find) printf '%s\n' "$row" ;;
  move)
    key="${3:-}"
    [[ -n "$key" ]] || die "usage: card.sh move ISSUE STATUS_KEY"
    opt="$(status_id "$key")"; name="$(status_name "$key")"
    gh project item-edit --project-id "$(cfg .projectId)" \
      --field-id "$(cfg .statusFieldId)" \
      --single-select-option-id "$opt" \
      --id "${row%%$'\t'*}" >/dev/null
    echo "moved #$issue → $name" ;;
esac
