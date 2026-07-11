#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

usage='usage: board-reconcile.sh OWNER PROJECT_NUMBER MAPPING_JSON_FILE  (mapping = {"canonicalKey": "Existing Column Name"})'
[[ $# -eq 3 ]] || die "$usage"
owner="$1"; number="$2"; mapfile="$3"

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

# Mapping must be a valid JSON object.
mapping="$(jq -e 'if type=="object" then . else error end' "$mapfile" 2>/dev/null)" \
  || die "invalid mapping: $mapfile is not a JSON object — $usage"

# Every KEY must be a canonical key.
bad_key="$(jq -r --argjson canon "$canon" \
  '($canon | map(.key)) as $ck | keys[] | select(. as $k | ($ck | index($k)) | not)' <<<"$mapping")"
[[ -z "$bad_key" ]] || die "unknown canonical key(s) in mapping: $(tr '\n' ' ' <<<"$bad_key")"

# Field id from field-list (ids are reliable here); option details come from a node query,
# because `field-list --format json` only returns {id,name} per option (no color/description).
fields="$(gh project field-list "$number" --owner "$owner" --limit 100 --format json)"
warn_capped "$(jq '.fields | length' <<<"$fields")" 100 "gh project field-list"
fid="$(jq -r '.fields[] | select(.name=="Status") | .id' <<<"$fields")"
[[ -n "$fid" && "$fid" != "null" ]] || die "no Status field on project $number"

# shellcheck disable=SC2016  # $fieldId is a GraphQL variable, not a shell expansion
existing="$(gh api graphql \
  -f query='query StatusOptions($fieldId: ID!) { node(id: $fieldId) { ... on ProjectV2SingleSelectField { options { id name color description } } } }' \
  -f fieldId="$fid" | jq -c '.data.node.options // []')"

# Every VALUE must name an option that actually exists on the board.
bad_val="$(jq -rn --argjson ex "$existing" --argjson map "$mapping" \
  '($ex | map(.name)) as $names | $map | to_entries[] | select(.value as $v | ($names | index($v)) | not) | .value')"
[[ -z "$bad_val" ]] || die "mapping value(s) not an existing option name: $(tr '\n' ' ' <<<"$bad_val")"

# Repeated VALUES would collapse in keyByName below, silently dropping a canonical column.
dup_val="$(jq -rn --argjson map "$mapping" '[$map[]] | group_by(.)[] | select(length>1) | .[0]')"
[[ -z "$dup_val" ]] || die "mapping produces duplicate mapping value(s): $(tr '\n' ' ' <<<"$dup_val") — each existing column maps to at most one canonical key"

# Kept options preserve their id (id match ⇒ value-preserving rename); appended canonicals carry none.
opts="$(jq -n --argjson existing "$existing" --argjson map "$mapping" --argjson canon "$canon" '
  ($map | to_entries | map({(.value): .key}) | add // {}) as $keyByName |
  ($canon | map({(.key): .name}) | add) as $nameByKey |
  ($existing | map(
    . as $o | ($keyByName[$o.name]) as $k |
    { id: $o.id,
      name: (if $k then $nameByKey[$k] else $o.name end),
      color: ($o.color // "GRAY"),
      description: ($o.description // "") }
  )) as $kept |
  ($kept | map(.name)) as $present |
  ($map | keys) as $mapped |
  ($canon | map(select(
    ((.key) as $k | ($mapped | index($k)) | not) and
    ((.name) as $n | ($present | index($n)) | not)
  )) | map({name, color, description})) as $appended |
  $kept + $appended')"

# A rename target that collides with a different existing option yields two same-named entries.
dupes="$(jq -rn --argjson opts "$opts" '[$opts[].name] | group_by(.)[] | select(length>1) | .[0]')"
[[ -z "$dupes" ]] || die "mapping produces duplicate option name(s): $(tr '\n' ' ' <<<"$dupes") — a rename target collides with an existing column"

jq -n --arg fid "$fid" --argjson opts "$opts" '{
  query: "mutation UpdateStatusOptions($fieldId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]!) { updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
  variables: { fieldId: $fid, opts: $opts }
}' | gh api graphql --input - >/dev/null

# Adopt path: boards without a Priority field get the canonical P1/P2/P3 one.
if [[ -z "$(jq -r '.fields[] | select(.name=="Priority") | .id' <<<"$fields")" ]]; then
  pid="$(gh project view "$number" --owner "$owner" --format json | jq -r '.id')"
  jq -n --arg pid "$pid" '{
    query: "mutation CreatePriorityField($projectId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]!) { createProjectV2Field(input: {projectId: $projectId, dataType: SINGLE_SELECT, name: \"Priority\", singleSelectOptions: $opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
    variables: { projectId: $pid, opts: [
      {name:"P1",color:"RED",description:""},
      {name:"P2",color:"YELLOW",description:""},
      {name:"P3",color:"GREEN",description:""}
    ]}}' | gh api graphql --input - >/dev/null
  echo "created Priority field" >&2
fi

echo "$opts"
