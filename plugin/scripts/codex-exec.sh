#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugin/scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  {
    echo "usage: codex-exec.sh preflight"
    echo "       codex-exec.sh detect"
    echo "       codex-exec.sh set-visibility <window|background>"
    echo "       codex-exec.sh session-id <log>"
    echo "       codex-exec.sh run --name <runner-model> --model <m> --out <report.md> --prompt-file <f> [--resume <session-id>] [--visibility <mode>] [--sandbox read-only|workspace-write] [--workdir <dir>]"
    echo "       codex-exec.sh render <log> <report> (internal: codex --json stream on stdin)"
  } >&2
  exit 2
}

preflight() {
  need codex
  codex login status >/dev/null 2>&1 || die_code3 "codex not authenticated — run: codex login"
  echo ok
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
  local name="" model="" out="" resume="" prompt_file="" vis="" sandbox_mode="read-only" workdir=""
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
      *) usage ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$out" && -n "$prompt_file" ]] || usage
  case "$sandbox_mode" in read-only|workspace-write) ;; *) usage ;; esac
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
  local cd_line=""
  [[ -n "$workdir" ]] && cd_line="cd $workdir || { echo 1 > $sentinel; exit 1; }"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
echo "=== $name ==="
$cd_line
$codex_cmd $sandbox -o $out - < $prompt_file 2>&1 | tee $log
echo "\${PIPESTATUS[0]}" > $sentinel
EOF
  chmod +x "$runner"

  case "$vis" in
    tmux)
      echo 'sleep 10' >> "$runner"   # pane lingers so the human can read the tail
      tmux split-window -d -v -l 15 "$runner" ;;
    iterm)
      osascript -e "tell application \"iTerm2\" to tell current session of current window to split horizontally with default profile command \"$runner\"" >/dev/null ;;
    window)
      osascript -e "tell application \"Terminal\" to do script \"$runner\"" >/dev/null ;;
    background)
      nohup "$runner" >/dev/null 2>&1 & ;;
    *) die "unknown visibility: $vis" ;;
  esac
  printf 'report=%s\nlog=%s\nsentinel=%s\nmode=%s\n' "$out" "$log" "$sentinel" "$vis"
}

case "${1:-}" in
  preflight) preflight ;;
  detect) detect ;;
  set-visibility) shift; set_visibility "$@" ;;
  session-id) shift; session_id "$@" ;;
  run) shift; run_codex "$@" ;;
  render) shift; render_stream "$@" ;;
  *) usage ;;
esac
