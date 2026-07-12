#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq; need git

OWNER="$(cfg .owner)"; REPO="$(cfg .repo)"; PROJECT="$(cfg .project)"
APPROVED="$(cfg '.labels.approved')"; QAPASSED="$(cfg '.labels.qaPassed')"
READYTOMERGE="$(cfg_or '.labels.readyToMerge' ready-to-merge)"
HERE="$(dirname "${BASH_SOURCE[0]}")"

S_HO="$(status_name humanOnly)"; S_IP="$(status_name inProgress)"
S_AR="$(status_name agentReview)"; S_QA="$(status_name qa)"
S_DN="$(status_name "done")";    S_AV="$(status_name archived)"

findings=0
flag() { findings=$((findings+1)); echo "DRIFT: $*"; }

closing_nodes() { # $1=issue -> nodes JSON array, or "ERR" on API failure
  # includeClosedPrs:false still returns MERGED PRs — filter state=="OPEN" explicitly downstream.
  local raw nodes
  # shellcheck disable=SC2016  # $o/$r/$n are GraphQL variables, not shell expansions
  raw=$(gh api graphql \
    -f query='query ClosingPRs($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){closedByPullRequestsReferences(first:10){nodes{state labels(first:10){nodes{name}}}}}}}' \
    -f o="$OWNER" -f r="$REPO" -F n="$1" 2>/dev/null) || { echo ERR; return; }
  nodes=$(jq -c '.data.repository.issue.closedByPullRequestsReferences.nodes // empty' <<<"$raw" 2>/dev/null) || { echo ERR; return; }
  [[ -n "$nodes" ]] || { echo ERR; return; }
  printf '%s' "$nodes"
}

has_unblock() { # $1=issue -> "yes"/"no" for an **Unblock:** comment, or "ERR" on API failure
  local raw
  raw=$(gh issue view "$1" -R "$OWNER/$REPO" --json comments 2>/dev/null) || { echo ERR; return; }
  if jq -e '[.comments[]? | select(.body | startswith("**Unblock:**"))] | length > 0' <<<"$raw" >/dev/null 2>&1; then
    echo yes
  else
    echo no
  fi
}

items_raw=$(gh project item-list "$PROJECT" --owner "$OWNER" --limit 200 --format json)
warn_capped "$(jq '.items | length' <<<"$items_raw")" 200 "gh project item-list"
items=$(jq -c '[.items[] | select(.content.type=="Issue") | {n: .content.number, status}]' <<<"$items_raw")
open_raw=$(gh issue list -R "$OWNER/$REPO" --state open --limit 300 --json number)
warn_capped "$(jq 'length' <<<"$open_raw")" 300 "gh issue list"
openset=$(jq -c '[.[].number]' <<<"$open_raw")

while IFS=$'\t' read -r n status; do
  isopen=$(jq -n --argjson o "$openset" --argjson n "$n" '$o | index($n) != null')
  if [[ "$status" == "$S_DN" ]]; then
    if [[ "$isopen" == true ]]; then flag "#$n is OPEN but sits in $S_DN"; fi
  elif [[ "$status" == "$S_AV" ]]; then
    :
  elif [[ "$isopen" == false ]]; then
    flag "#$n is CLOSED but sits in $status"
  else
    case "$status" in
      "$S_AR"|"$S_IP"|"$S_QA")
        nodes=$(closing_nodes "$n")
        if [[ "$nodes" == ERR ]]; then
          echo "WARN: #$n PR-link check failed — re-run" >&2
        else
          opencount=$(jq '[.[] | select(.state=="OPEN")] | length' <<<"$nodes")
          approved=$(jq --arg L "$APPROVED" '[.[] | select(.state=="OPEN") | .labels.nodes[]?.name] | index($L) != null' <<<"$nodes")
          case "$status" in
            "$S_AR")
              if [[ "$opencount" -eq 0 ]]; then flag "#$n in $S_AR has no open PR closing it"; fi ;;
            "$S_IP")
              if [[ "$opencount" -gt 0 ]]; then flag "#$n in $S_IP has an open PR — move to $S_AR?"; fi ;;
            "$S_QA")
              if [[ "$opencount" -eq 0 ]]; then
                flag "#$n in $S_QA has no open PR closing it"
              elif [[ "$approved" != true ]]; then
                flag "#$n in $S_QA has an open PR but none carries the approved label"
              fi ;;
          esac
        fi ;;
      "$S_HO")
        case "$(has_unblock "$n")" in
          ERR) echo "WARN: #$n unblock-comment check failed — re-run" >&2 ;;
          no)  flag "#$n in $S_HO has no Unblock: comment" ;;
        esac ;;
    esac
  fi
done < <(jq -r '.[] | "\(.n)\t\(.status)"' <<<"$items")

# R7: configured status/priority option ids absent from the live board.
discover=$("$HERE/board-discover.sh" "$OWNER" "$PROJECT" 2>/dev/null) || discover=""
if [[ -n "$discover" ]]; then
  live=$(jq -c '[.status[]?.id, .priority[]?.id] | map(select(. != null))' <<<"$discover")
  if [[ -z "$(jq -r '.priorityFieldId // empty' <<<"$discover")" ]]; then
    flag "live board has no Priority field — fix: re-run /conveyor:init (board-reconcile creates it)"
  fi
  if [[ -z "$(jq -r '.priority // empty' "$CONVEYOR_CONFIG")" ]]; then
    flag "config has no priority mapping — fix: re-run board-discover.sh and update .claude/conveyor.json"
  fi
  while IFS=$'\t' read -r key id; do
    present=$(jq -n --argjson l "$live" --arg id "$id" '$l | index($id) != null')
    if [[ "$present" != true ]]; then flag "config status '$key' id $id absent from live board"; fi
  done < <(jq -r '.status | to_entries[] | "\(.key)\t\(.value.id)"' "$CONVEYOR_CONFIG")
  while IFS=$'\t' read -r key id; do
    present=$(jq -n --argjson l "$live" --arg id "$id" '$l | index($id) != null')
    if [[ "$present" != true ]]; then flag "config priority '$key' id $id absent from live board"; fi
  done < <(jq -r '.priority // {} | to_entries[] | "\(.key)\t\(.value.id)"' "$CONVEYOR_CONFIG")
else
  echo "WARN: config staleness check failed — re-run" >&2
fi

# R8: CLAUDE.md marker block — both markers or neither; one alone is broken.
if [[ -f CLAUDE.md ]]; then
  b=$(grep -c -- '<!-- conveyor:begin -->' CLAUDE.md || true)
  e=$(grep -c -- '<!-- conveyor:end -->' CLAUDE.md || true)
  if { [[ "$b" -gt 0 && "$e" -eq 0 ]] || [[ "$b" -eq 0 && "$e" -gt 0 ]]; }; then
    flag "CLAUDE.md conveyor marker block is broken (one marker without the other)"
  fi
fi

# R9b: pre-0.1.13 configs lack the readyToMerge label key — the scripts default it,
# but flag it so the config is brought current.
if [[ -z "$(jq -r '.labels.readyToMerge // empty' "$CONVEYOR_CONFIG")" ]]; then
  flag "config .labels.readyToMerge missing — fix: jq '.labels.readyToMerge = \"ready-to-merge\"' $CONVEYOR_CONFIG > tmp && mv tmp $CONVEYOR_CONFIG"
fi

# R9: configured labels must exist on the repo.
labels=$(gh label list -R "$OWNER/$REPO" --limit 200 --json name 2>/dev/null) || labels=ERR
if [[ "$labels" == ERR ]]; then
  echo "WARN: label check failed — re-run" >&2
else
  for L in "$APPROVED" "$QAPASSED" "$READYTOMERGE"; do
    present=$(jq --arg L "$L" 'any(.[]?; .name==$L)' <<<"$labels")
    if [[ "$present" != true ]]; then
      flag "label '$L' missing — fix: gh label create '$L' --force -R $OWNER/$REPO"
    fi
  done
fi

# R10: orphaned worktrees — a linked worktree under .claude/worktrees/ whose branch has no open PR (advisory; local leftovers aren't board drift).
wt=$(git worktree list --porcelain 2>/dev/null) || wt=ERR
if [[ "$wt" == ERR ]]; then
  echo "WARN: worktree check failed — re-run" >&2
else
  while IFS=$'\t' read -r wpath wbranch; do
    case "$wpath" in */.claude/worktrees/*) ;; *) continue ;; esac
    case "${wpath##*/}" in agent-*) continue ;; esac
    [[ -n "$wbranch" ]] || continue
    short="${wbranch#refs/heads/}"
    prs=$(gh pr list -R "$OWNER/$REPO" --head "$short" --state open --json number 2>/dev/null) || prs=ERR
    if [[ "$prs" == ERR ]]; then
      echo "WARN: worktree $wpath PR check failed — re-run" >&2
    elif [[ "$(jq 'length' <<<"$prs")" -eq 0 ]]; then
      echo "WARN: orphaned worktree $wpath — branch $short has no open PR; git worktree remove it" >&2
    fi
  done < <(awk '
    /^worktree / { p=substr($0,10); b="" }
    /^branch /   { b=$2 }
    /^$/         { if (p != "") print p "\t" b; p=""; b="" }
    END          { if (p != "") print p "\t" b }' <<<"$wt")
fi

installed="$(jq -r '.version // empty' "$HERE/../.claude-plugin/plugin.json" 2>/dev/null || true)"
stamped="$(jq -r '.pluginVersion // empty' "$CONVEYOR_CONFIG" 2>/dev/null || true)"
if [[ -n "$installed" && "$stamped" != "$installed" && \
      "$(printf '%s\n%s\n' "$installed" "${stamped:-0}" | sort -V | tail -n1)" == "$installed" ]]; then
  tmp=$(mktemp)
  jq --arg v "$installed" '.pluginVersion = $v' "$CONVEYOR_CONFIG" > "$tmp" && mv "$tmp" "$CONVEYOR_CONFIG"
  echo "board-doctor: stamped pluginVersion ${stamped:-unstamped} → $installed — commit .claude/conveyor.json"
fi

if [[ "$findings" -eq 0 ]]; then
  echo "board-doctor: no drift ($(jq length <<<"$items") issue cards checked)"
  exit 0
fi
exit 1
