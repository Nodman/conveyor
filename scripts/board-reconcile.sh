#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq
owner="$1"; number="$2"; mapfile="$3"
mapping="$(cat "$mapfile")"

canon='[
  {"key":"humanOnly","name":"Human Only","color":"PINK","description":"Blocked on a human action"},
  {"key":"backlog","name":"Backlog","color":"GRAY","description":"Not dev-ready"},
  {"key":"ready","name":"Ready for dev","color":"BLUE","description":"Groomed, pickable"},
  {"key":"inProgress","name":"In Progress","color":"YELLOW","description":"Agent working"},
  {"key":"agentReview","name":"Agent Review","color":"ORANGE","description":"PR open, review loop"},
  {"key":"qa","name":"QA","color":"PURPLE","description":"Review approved, QA on PR branch"},
  {"key":"done","name":"Done","color":"GREEN","description":"Automation only"},
  {"key":"archived","name":"Archived","color":"RED","description":"Trash"}
]'

fields=$(gh project field-list "$number" --owner "$owner" --format json)
fid=$(jq -r '.fields[] | select(.name=="Status") | .id' <<<"$fields")
existing=$(jq -c '[.fields[] | select(.name=="Status") | .options[] | {name, color, description}]' <<<"$fields")

# GitHub matches options by NAME on update — preserving existing names/colors verbatim is what keeps item values alive.
opts=$(jq -n --argjson existing "$existing" --argjson map "$mapping" --argjson canon "$canon" '
  ($map | to_entries | map({(.value): .key}) | add // {}) as $keyByName |
  ($canon | map({(.key): .name}) | add) as $nameByKey |
  ($existing | map(
    . as $o | ($keyByName[$o.name]) as $k |
    if $k then {name: $nameByKey[$k], color: $o.color, description: $o.description} else $o end
  )) as $kept |
  ($kept | map(.name)) as $present |
  ($map | keys) as $mapped |
  ($canon | map(select(
    ((.key) as $k | ($mapped | index($k)) | not) and
    ((.name) as $n | ($present | index($n)) | not)
  )) | map({name, color, description})) as $appended |
  $kept + $appended')

jq -n --arg fid "$fid" --argjson opts "$opts" '{
  query: "mutation UpdateStatusOptions($fieldId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]) { updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
  variables: { fieldId: $fid, opts: $opts }
}' | gh api graphql --input - >/dev/null

echo "$opts"
