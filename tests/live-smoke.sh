#!/usr/bin/env bash
set -euo pipefail
# Real-gh end-to-end smoke: create a throwaway repo + project, run the full
# board/scaffold/doctor path against them, then tear it all down.
# Offline by default — set RUN_LIVE=1 to actually touch GitHub.

[[ "${RUN_LIVE:-}" == "1" ]] || { echo "skipped (set RUN_LIVE=1)"; exit 0; }

command -v gh >/dev/null || { echo "smoke: missing dependency: gh" >&2; exit 1; }
command -v jq >/dev/null || { echo "smoke: missing dependency: jq" >&2; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="conveyor-smoke-$$"
owner="$(gh api user --jq .login)"
number=""; workdir=""; tmproot=""

fail() { echo "smoke: FAIL — $*" >&2; exit 1; }
step() { echo "smoke: $*"; }

teardown() {
  local code=$?
  set +e
  echo "smoke: teardown"
  if [[ -n "$number" ]]; then
    if gh project delete "$number" --owner "$owner" >/dev/null 2>&1; then
      echo "  deleted project $number"
    else
      echo "  WARN: could not delete project $number (delete it by hand)"
    fi
  fi
  if gh repo delete "$owner/$scratch" --yes >/dev/null 2>&1; then
    echo "  deleted repo $owner/$scratch"
  else
    echo "  WARN: could not delete repo $owner/$scratch — the token lacks the delete_repo scope."
    echo "  Manual cleanup: gh auth refresh -h github.com -s delete_repo && gh repo delete $owner/$scratch --yes"
  fi
  [[ -n "$tmproot" ]] && rm -rf "$tmproot"
  exit "$code"
}
trap teardown EXIT

# 1. Throwaway private repo.
step "creating repo $owner/$scratch"
gh repo create "$scratch" --private --add-readme >/dev/null || fail "gh repo create"

# 2. Board (project + Status/Priority option sets).
step "board-create"
number="$("$ROOT/scripts/board-create.sh" "$owner" "$scratch" "$scratch")" || fail "board-create.sh"
[[ "$number" =~ ^[0-9]+$ ]] || fail "board-create did not echo a project number (got: $number)"

# 3. Discover — every status + priority option must resolve to an id.
step "board-discover (#$number)"
disc="$("$ROOT/scripts/board-discover.sh" "$owner" "$number")" || fail "board-discover.sh"
jq -e '([.status[] | select(.id != null)] | length) == 8
   and ([.priority[]? | select(.id != null)] | length) == 3' <<<"$disc" >/dev/null \
  || fail "discover: expected 8 status + 3 priority ids, got $(jq -c '{s:[.status[]|select(.id!=null)]|length, p:[.priority[]?|select(.id!=null)]|length}' <<<"$disc")"

# 4. Clone the scratch repo and drop a composed config in it.
tmproot="$(mktemp -d)"
workdir="$tmproot/repo"
step "clone into $workdir"
gh repo clone "$owner/$scratch" "$workdir" -- -q || fail "gh repo clone"
cfgpath="$workdir/.claude/conveyor.json"
mkdir -p "$workdir/.claude"
jq -n --argjson disc "$disc" --arg owner "$owner" --arg repo "$scratch" --argjson number "$number" \
  '$disc + {owner:$owner, repo:$repo, project:$number,
            labels:{approved:"approved-by-agent", qaPassed:"qa-passed"},
            mergePolicy:"solo", qaSkipPaths:["docs/**"]}' > "$cfgpath" || fail "compose config"

# 5. Scaffold — docs, issue template, labels, CLAUDE.md block (run inside the clone).
step "scaffold"
( cd "$workdir" && CONVEYOR_CONFIG="$cfgpath" "$ROOT/scripts/scaffold.sh" ) || fail "scaffold.sh"
[[ -f "$workdir/CLAUDE.md" ]] || fail "scaffold left no CLAUDE.md"
[[ -f "$workdir/.github/ISSUE_TEMPLATE/agent-task.yml" ]] || fail "scaffold left no issue template"

# 6. Doctor — a fresh, consistent board must report no drift.
step "board-doctor"
out="$( cd "$workdir" && CONVEYOR_CONFIG="$cfgpath" "$ROOT/scripts/board-doctor.sh" )" \
  || fail "board-doctor exited non-zero: $out"
grep -q "no drift" <<<"$out" || fail "board-doctor did not report 'no drift': $out"

# 7. claude-block idempotency — re-applying the same block must not change the file.
step "claude-block idempotency"
before="$(shasum "$workdir/CLAUDE.md")"
sed "s|{{OWNER_PROJECT}}|$owner/$number|g" "$ROOT/templates/claude-block.md" \
  | ( cd "$workdir" && CONVEYOR_CONFIG="$cfgpath" "$ROOT/scripts/claude-block.sh" CLAUDE.md ) \
  || fail "claude-block.sh re-run"
after="$(shasum "$workdir/CLAUDE.md")"
[[ "${before%% *}" == "${after%% *}" ]] || fail "claude-block is not idempotent — CLAUDE.md changed on re-run"

step "PASS — all asserts green"
