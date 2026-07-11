#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq
owner="$1"; repo="$2"; title="$3"

proj=$(gh project create --owner "$owner" --title "$title" --format json)
number=$(jq -r .number <<<"$proj"); pid=$(jq -r .id <<<"$proj")
gh project link "$number" --owner "$owner" --repo "$repo" >/dev/null

status_field=$(gh project field-list "$number" --owner "$owner" --format json \
  | jq -r '.fields[] | select(.name=="Status") | .id')

# Full replacement is safe here: the project is brand new (no items carry values yet).
jq -n --arg fid "$status_field" '{
  query: "mutation UpdateStatusOptions($fieldId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]!) { updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
  variables: { fieldId: $fid, opts: [
    {name:"Human Only",color:"PINK",description:"Blocked on a human action"},
    {name:"Backlog",color:"GRAY",description:"Not dev-ready"},
    {name:"Ready for dev",color:"BLUE",description:"Groomed, pickable"},
    {name:"In Progress",color:"YELLOW",description:"Agent working"},
    {name:"Agent Review",color:"ORANGE",description:"PR open, review loop"},
    {name:"QA",color:"PURPLE",description:"Review approved, QA on PR branch"},
    {name:"Done",color:"GREEN",description:"Automation only"},
    {name:"Archived",color:"RED",description:"Trash"}
  ]}}' | gh api graphql --input - >/dev/null

jq -n --arg pid "$pid" '{
  query: "mutation CreatePriorityField($projectId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]!) { createProjectV2Field(input: {projectId: $projectId, dataType: SINGLE_SELECT, name: \"Priority\", singleSelectOptions: $opts}) { projectV2Field { ... on ProjectV2SingleSelectField { id } } } }",
  variables: { projectId: $pid, opts: [
    {name:"P1",color:"RED",description:""},
    {name:"P2",color:"YELLOW",description:""},
    {name:"P3",color:"GREEN",description:""}
  ]}}' | gh api graphql --input - >/dev/null

echo "$number"
