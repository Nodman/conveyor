#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

cmd="${1:-}"; issue="${2:-}"
[[ "$cmd" == "find" || "$cmd" == "move" ]] || die "usage: card.sh find|move ISSUE [STATUS_KEY]"
[[ -n "$issue" ]] || die "usage: card.sh find|move ISSUE [STATUS_KEY]"

row="$("$(dirname "${BASH_SOURCE[0]}")/board-items.sh" find "$issue")"

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
