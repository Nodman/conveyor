#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=plugin/scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need gh; need jq

dry=0; grant_perms=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --grant-label-perms) grant_perms=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done

here="$(dirname "$0")"
tpl="$here/../templates"

owner="$(cfg .owner)"
project="$(cfg .project)"
approved="$(cfg .labels.approved)"
qa_passed="$(cfg .labels.qaPassed)"
ready_to_merge="$(cfg_or .labels.readyToMerge ready-to-merge)"
sub="s|{{OWNER_PROJECT}}|$owner/$project|g"

say() { if [[ $dry -eq 1 ]]; then echo "scaffold: [dry-run] $*"; else echo "scaffold: $*"; fi; }
run() { [[ $dry -eq 1 ]] && return 0; "$@"; }

# 1. Doc directories.
say "mkdir docs/specs docs/plans docs/gotchas"
run mkdir -p docs/specs docs/plans docs/gotchas

# 2. Seed docs — only if absent, never overwrite.
seed() { # template dest
  if [[ -e "$2" ]]; then
    echo "scaffold: skip $2 (exists)"
  else
    say "create $2"
    run cp "$1" "$2"
  fi
}
seed "$tpl/DECISIONS.md" docs/DECISIONS.md
seed "$tpl/gotchas-README.md" docs/gotchas/README.md

# 3. Issue template — generated, config-owned: always (re)write.
say "write .github/ISSUE_TEMPLATE/agent-task.yml"
if [[ $dry -eq 0 ]]; then
  mkdir -p .github/ISSUE_TEMPLATE
  sed "$sub" "$tpl/agent-task.yml" > .github/ISSUE_TEMPLATE/agent-task.yml
fi

# 4. Labels.
label() { # name color desc
  say "label create $1"
  run gh label create "$1" --force --color "$2" --description "$3" >/dev/null
}
label "$approved" 0E8A16 "PR approved by the review agent"
label "$qa_passed" 5319E7 "QA passed on the PR branch"
label "$ready_to_merge" FBCA04 "All agent gates passed; awaiting human merge"

# 5. CLAUDE.md conveyor block (idempotent via claude-block.sh).
say "CLAUDE.md conveyor block"
if [[ $dry -eq 0 ]]; then
  sed "$sub" "$tpl/claude-block.md" | "$here/claude-block.sh" CLAUDE.md
fi

# 6. Gitignore the agent worktree dir — append once.
gi=.gitignore
if [[ -f "$gi" ]] && grep -qxF '.claude/worktrees/' "$gi"; then
  echo "scaffold: skip $gi (.claude/worktrees/ present)"
else
  say "add .claude/worktrees/ to $gi"
  if [[ $dry -eq 0 ]]; then printf '.claude/worktrees/\n' >> "$gi"; fi
fi

# 7. Label permissions — opt-in only (consent handled by the init/doctor skills).
if [[ $grant_perms -eq 1 ]]; then
  say "grant label permissions in .claude/settings.json"
  if [[ $dry -eq 0 ]]; then
    mkdir -p .claude
    s=.claude/settings.json
    [[ -s "$s" ]] || echo '{}' > "$s"
    tmp=$(mktemp)
    rule="Conveyor board lifecycle writes to this project's own GitHub repo are pre-authorized by the user's standing workflow (CLAUDE.md): gh issue create/comment/edit, gh pr create/comment/edit, label add/remove, board card moves via gh project or card.sh, and pushing feature branches. This includes filing backlog issues for out-of-scope findings discovered during a task — the workflow mandates it. Merging PRs and moving cards to Done remain human-only and are NOT covered."
    jq --arg rule "$rule" '.permissions.allow = ((.permissions.allow // []) +
        (["Bash(gh pr edit:*)","Bash(gh issue edit:*)","Bash(gh issue comment:*)","Bash(gh issue create:*)"] - (.permissions.allow // [])))
      | .autoMode.allow = ((.autoMode.allow // []) +
        (["$defaults", $rule] - (.autoMode.allow // [])))' \
      "$s" > "$tmp" && mv "$tmp" "$s"
  fi
fi
