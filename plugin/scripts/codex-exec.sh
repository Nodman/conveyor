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
    echo "       codex-exec.sh run --name <runner-model> --model <m> --out <report.md> --prompt-file <f> [--resume <session-id>] [--visibility <mode>]"
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

run_codex() {
  local name="" model="" out="" resume="" prompt_file="" vis=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --resume) resume="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --visibility) vis="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$out" && -n "$prompt_file" ]] || usage
  [[ -f "$prompt_file" ]] || die "no prompt file: $prompt_file"
  case "$out$prompt_file" in *" "*) die "paths must not contain spaces" ;; esac
  if [[ -z "$vis" ]]; then vis="$(detect)"; fi
  if [[ "$vis" == "unset" ]]; then vis=background; fi

  local log="${out%.md}.log" sentinel="$out.done" runner="${out%.md}.run.sh"
  rm -f "$out" "$sentinel"
  local codex_cmd="codex exec -m $model" sandbox="-s read-only"
  # resume subcommand rejects -s; set the sandbox via config instead
  if [[ -n "$resume" ]]; then codex_cmd="codex exec resume $resume"; sandbox="-c 'sandbox_mode=\"read-only\"'"; fi
  cat > "$runner" <<EOF
#!/usr/bin/env bash
echo "=== $name ==="
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
  *) usage ;;
esac
