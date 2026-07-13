#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugin/scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  {
    echo "usage: codex-exec.sh preflight [--escalations <exec|review>]"
    echo "       codex-exec.sh detect"
    echo "       codex-exec.sh set-visibility <window|background>"
    echo "       codex-exec.sh session-id <log>"
    echo "       codex-exec.sh render-policy <exec|review> --name <n> --workdir <d> [--pr <n> --issue <n>]"
    echo "       codex-exec.sh run --name <runner-model> --model <m> --out <report.md> --prompt-file <f> [--resume <session-id>] [--visibility <mode>] [--sandbox read-only|workspace-write] [--workdir <dir>] [--role exec|review --pr <n> --issue <n>] [--output-schema <f>]"
    echo "       codex-exec.sh audit <log>"
    echo "       codex-exec.sh render <log> <report> (internal: codex --json stream on stdin)"
  } >&2
  exit 2
}

render_policy() {
  local role="${1:-}"; shift 2>/dev/null || true
  case "$role" in exec|review) ;; *) usage ;; esac
  local name="" workdir="" pr="" issue=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --workdir) workdir="$2"; shift 2 ;;
      --pr) pr="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  local tpl="$SCRIPT_DIR/../config/codex-policies/$role.policy.txt"
  [[ -f "$tpl" ]] || die "no policy template: $tpl"
  [[ -n "$name" && -n "$workdir" ]] || usage
  [[ "$role" == exec || ( -n "$pr" && -n "$issue" ) ]] || usage
  local out
  out="$(sed -e "s|AGENT_NAME|$name|g" -e "s|WORKTREE|$workdir|g" \
    -e "s|PR_NUMBER|$pr|g" -e "s|ISSUE_NUMBER|$issue|g" \
    -e "s|OWNER|$(cfg .owner)|g" -e "s|REPO|$(cfg .repo)|g" \
    -e "s|LABEL_APPROVED|$(cfg '.labels.approved')|g" "$tpl")"
  grep -qE '(AGENT_NAME|OWNER|REPO|PR_NUMBER|ISSUE_NUMBER|WORKTREE|LABEL_APPROVED)' <<<"$out" \
    && die "render-policy: unfilled placeholder in $role policy"
  printf '%s\n' "$out"
}

preflight() {
  need codex
  codex login status >/dev/null 2>&1 || die_code3 "codex not authenticated — run: codex login"
  echo ok
}

preflight_escalations() {
  local role="${1:-}"
  case "$role" in exec|review) ;; *) usage ;; esac
  need codex
  local cache_dir="$PWD/.conveyor/canary"
  local scratch; scratch="$(mktemp -d)"
  local policy
  if [[ "$role" == exec ]]; then
    git init -q "$scratch" 2>/dev/null || true
    policy="$(render_policy exec --name "canary-$role" --workdir "$scratch")"
  else
    policy="$(render_policy review --name "canary-$role" --workdir "$scratch" --pr 0 --issue 0)"
  fi
  local sha; sha="$(printf '%s' "$policy" | shasum 2>/dev/null | awk '{print $1}')"
  sha="${sha:0:12}"; [[ -n "$sha" ]] || sha="nosha"
  local ver; ver="$(codex --version 2>/dev/null | tr -dc 'A-Za-z0-9.')"
  [[ -n "$ver" ]] || ver="unknown"
  local prompt="$scratch/canary-prompt.md"
  if [[ "$role" == exec ]]; then
    printf 'Prove escalated commits work: run this and nothing else: git commit --allow-empty -m canary\n' > "$prompt"
  else
    printf 'Prove escalated reads work: run this and nothing else: gh api repos/%s/%s\n' "$(cfg .owner)" "$(cfg .repo)" > "$prompt"
  fi
  local out="$scratch/canary.out" pj
  pj="$(printf '%s' "$policy" | jq -Rs .)"
  ( cd "$scratch" && codex exec -m canary -s workspace-write --strict-config \
      -c 'approval_policy="on-request"' -c 'approvals_reviewer="auto_review"' \
      -c "auto_review.policy=$pj" --json - < "$prompt" ) > "$out" 2>&1 || true
  if grep -qF 'Approval policy is currently never' "$out"; then
    die_code3 "canary $role: auto_review not active (misconfig) — escalations denied; fix approval_policy/approvals_reviewer or use the advisory fallback"
  fi
  # PASS = the role's privileged command ran AND succeeded; a denied escalation
  # still executes the command but it fails (network/.git blocked), so exit 0 is the real signal
  local pat="gh "; [[ "$role" == exec ]] && pat="git commit"
  local passed="" line c rc
  while IFS= read -r line; do
    jq -e . >/dev/null 2>&1 <<<"$line" || continue
    [[ "$(jq -r '.type // empty' <<<"$line" 2>/dev/null)" == item.completed ]] || continue
    [[ "$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)" == command_execution ]] || continue
    c="$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null)"
    rc="$(jq -r '.item.exit_code // 1' <<<"$line" 2>/dev/null)"
    [[ "$c" == *"$pat"* && "$rc" == 0 ]] && { passed=1; break; }
  done < "$out"
  [[ -n "$passed" ]] || die_code3 "canary $role: auto_review not active — escalated command did not execute successfully"
  mkdir -p "$cache_dir"
  : > "$cache_dir/$role.$ver.$sha"
  echo ok
}

audit() {
  local log="${1:-}"
  [[ -f "$log" ]] || die "no log file: $log"
  local found="" line t it cmd rc
  while IFS= read -r line; do
    jq -e . >/dev/null 2>&1 <<<"$line" || continue
    t="$(jq -r '.type // empty' <<<"$line" 2>/dev/null)"
    [[ "$t" == item.completed ]] || continue
    it="$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)"
    [[ "$it" == command_execution ]] || continue
    cmd="$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null)"
    rc="$(jq -r '.item.exit_code // 0' <<<"$line" 2>/dev/null)"
    # substring, not prefix: codex wraps commands as `/bin/zsh -lc '<cmd>'`
    case "$cmd" in
      *"gh "*|*"curl "*|*"wget "*|*"nc "*|*"ssh "*|*"git commit"*)
        printf '%s\t%s\n' "$rc" "$cmd"; found=1 ;;
    esac
  done < "$log"
  [[ -n "$found" ]] || echo none
}

detect() {
  if [[ -n "${TMUX:-}" ]]; then echo tmux
  elif [[ "${LC_TERMINAL:-}" == "iTerm2" || "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then echo iterm
  else cfg_or '.externalAgents.fallbackVisibility' unset
  fi
}

set_visibility() {
  case "${1:-}" in window|background) ;; *) usage ;; esac
  [[ -f "$CONVEYOR_CONFIG" ]] || die "no $CONVEYOR_CONFIG — run /conveyor:init first"
  local tmp; tmp="$(mktemp)"
  jq --arg v "$1" '.externalAgents.fallbackVisibility = $v' "$CONVEYOR_CONFIG" > "$tmp"
  mv "$tmp" "$CONVEYOR_CONFIG"
  echo "externalAgents.fallbackVisibility=$1"
}

session_id() {
  [[ -f "${1:-}" ]] || die "no log file: ${1:-}"
  grep -m1 '^session id: ' "$1" | awk '{print $3}' | grep . || die "no session id in $1"
}

render_stream() {
  set +e   # a display bug must never SIGPIPE-kill the codex run
  local log="${1:?}" report="${2:-}"
  local B="" R="" G="" C="" D="" N=""
  if [[ -t 1 ]]; then
    B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; C=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
  fi
  : > "$log"
  local line type itype txt cmd rc
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$log"
    if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
      printf '%s! %s%s\n\n' "$D" "$line" "$N"
      continue
    fi
    type=$(jq -r '.type // empty' <<<"$line" 2>/dev/null)
    case "$type" in
      thread.started)
        txt=$(jq -r '.thread_id // empty' <<<"$line" 2>/dev/null)
        if [[ -n "$txt" ]]; then
          printf 'session id: %s\n' "$txt" >> "$log"
          printf '%ssession %s%s\n\n' "$B" "$txt" "$N"
        fi ;;
      item.started|item.completed)
        itype=$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)
        case "$itype" in
          command_execution)
            cmd=$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-120)
            if [[ "$type" == item.started && -n "$cmd" ]]; then
              printf '%s$ %s%s\n\n' "$C" "$cmd" "$N"
            elif [[ "$type" == item.completed ]]; then
              rc=$(jq -r '.item.exit_code // 0' <<<"$line" 2>/dev/null)
              if [[ "$rc" != 0 ]]; then printf '%s! exit %s: %s%s\n\n' "$R" "$rc" "$cmd" "$N"; fi
            fi ;;
          file_change)
            if [[ "$type" == item.completed ]]; then
              jq -r --arg pwd "$PWD/" '.item.changes[]? | "\(.kind) \(.path | ltrimstr($pwd))"' <<<"$line" 2>/dev/null |
                while IFS= read -r txt; do printf '%s+ %s%s\n' "$G" "$txt" "$N"; done
              printf '\n'
            fi ;;
          agent_message)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null)
              if [[ -n "$txt" ]]; then printf '%s%s%s\n\n' "$C" "$txt" "$N"; fi
            fi ;;
          reasoning)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-160)
              if [[ -n "$txt" ]]; then printf '%s* %s%s\n\n' "$D" "$txt" "$N"; fi
            fi ;;
          todo_list)
            txt=$(jq -r '[.item.items[]? | select(.completed == false)][0].text // empty' <<<"$line" 2>/dev/null)
            if [[ -n "$txt" ]]; then printf '%s> %s%s\n\n' "$D" "$txt" "$N"; fi ;;
        esac ;;
      turn.completed)
        txt=$(jq -r '"\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out"' <<<"$line" 2>/dev/null)
        printf '%sdone: %s%s\n\n' "$G" "$txt" "$N" ;;
      error)
        txt=$(jq -r '.message // "unknown error"' <<<"$line" 2>/dev/null)
        printf '%sERROR %s%s\n\n' "$R" "$txt" "$N" ;;
    esac
  done
  if [[ -n "$report" ]]; then printf '%sreport: %s%s\n' "$D" "$report" "$N"; fi
  return 0
}

run_codex() {
  local name="" model="" out="" resume="" prompt_file="" vis="" sandbox_mode="read-only" workdir="" pane=""
  local role="" pr="" issue="" output_schema=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --resume) resume="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --visibility) vis="$2"; shift 2 ;;
      --sandbox) sandbox_mode="$2"; shift 2 ;;
      --workdir) workdir="$2"; shift 2 ;;
      --role) role="$2"; shift 2 ;;
      --pr) pr="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      --output-schema) output_schema="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$out" && -n "$prompt_file" ]] || usage
  case "$sandbox_mode" in read-only|workspace-write) ;; *) usage ;; esac
  case "$role" in ""|exec|review) ;; *) usage ;; esac
  [[ -z "$output_schema" || -f "$output_schema" ]] || die "no output schema: $output_schema"
  [[ -f "$prompt_file" ]] || die "no prompt file: $prompt_file"
  [[ -z "$workdir" || -d "$workdir" ]] || die "no workdir: $workdir"
  # runner cd's to workdir, so relative --out/--prompt-file would resolve there
  [[ -z "$workdir" || ( "$out" == /* && "$prompt_file" == /* ) ]] || die "absolute --out/--prompt-file required with --workdir"
  case "$out$prompt_file$workdir" in *" "*) die "paths must not contain spaces" ;; esac
  if [[ -z "$vis" ]]; then vis="$(detect)"; fi
  if [[ "$vis" == "unset" ]]; then vis=background; fi

  local log="${out%.md}.log" sentinel="$out.done" runner="${out%.md}.run.sh"
  rm -f "$out" "$sentinel"
  local codex_cmd="codex exec -m $model" sandbox="-s $sandbox_mode"
  # resume subcommand rejects -s; set the sandbox via config instead
  if [[ -n "$resume" ]]; then codex_cmd="codex exec resume $resume"; sandbox="-c 'sandbox_mode=\"$sandbox_mode\"'"; fi
  local role_flags="" schema_flag=""
  if [[ -n "$role" ]]; then
    local policy_json="${out%.md}.policy.json"
    render_policy "$role" --name "$name" --workdir "$workdir" \
      ${pr:+--pr "$pr"} ${issue:+--issue "$issue"} | jq -Rs . > "$policy_json"
    # \$(cat …) stays literal in the runner: policy is read at run time, no heredoc quoting fight
    role_flags="--strict-config -c 'approval_policy=\"on-request\"' -c 'approvals_reviewer=\"auto_review\"' -c \"auto_review.policy=\$(cat $policy_json)\""
  fi
  [[ -n "$output_schema" ]] && schema_flag="--output-schema $output_schema"
  local pat_svc; pat_svc="$(cfg_or '.externalAgents.codexPatService' '')"
  local env_line=""
  if [[ -n "$pat_svc" ]]; then
    # security lookup runs at run time; \$( ) stays literal in the runner
    env_line="export GH_TOKEN=\"\$(security find-generic-password -s $pat_svc -w)\" GH_CONFIG_DIR=${out%.md}.ghcfg"
  fi
  local cd_line=""
  [[ -n "$workdir" ]] && cd_line="cd $workdir || { echo 1 > $sentinel; exit 1; }"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
echo "=== $name ==="
$cd_line
$env_line
printf '\e[2m--- prompt ---\n'
cat $prompt_file
printf -- '--------------\e[0m\n'
$codex_cmd $sandbox $role_flags $schema_flag --json -o $out - < $prompt_file 2>&1 | $SCRIPT_DIR/codex-exec.sh render $log $out
echo "\${PIPESTATUS[0]}" > $sentinel
EOF
  chmod +x "$runner"

  case "$vis" in
    tmux)
      echo 'sleep 10' >> "$runner"   # pane lingers so the human can read the tail
      pane="$(tmux split-window -d -h -l 40% -P -F '#{pane_id}' "$runner")"
      tmux select-pane -t "$pane" -T "$name" || true ;;
    iterm)
      osascript \
        -e 'tell application "iTerm2"' \
        -e 'tell current session of current window' \
        -e "set newSession to split vertically with default profile command \"$runner\"" \
        -e 'end tell' \
        -e "set name of newSession to \"$name\"" \
        -e 'end tell' >/dev/null ;;
    window)
      osascript -e "tell application \"Terminal\" to do script \"$runner\"" >/dev/null ;;
    background)
      nohup "$runner" >/dev/null 2>&1 & ;;
    *) die "unknown visibility: $vis" ;;
  esac
  printf 'report=%s\nlog=%s\nsentinel=%s\nmode=%s\n' "$out" "$log" "$sentinel" "$vis"
}

case "${1:-}" in
  preflight)
    shift
    if [[ "${1:-}" == "--escalations" ]]; then shift; preflight_escalations "$@"; else preflight; fi ;;
  detect) detect ;;
  set-visibility) shift; set_visibility "$@" ;;
  session-id) shift; session_id "$@" ;;
  render-policy) shift; render_policy "$@" ;;
  audit) shift; audit "$@" ;;
  run) shift; run_codex "$@" ;;
  render) shift; render_stream "$@" ;;
  *) usage ;;
esac
