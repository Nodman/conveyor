#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  grep -m1 '^session id: ' "$1" | awk '{print $3}'
}

case "${1:-}" in
  preflight) preflight ;;
  detect) detect ;;
  set-visibility) shift; set_visibility "$@" ;;
  session-id) shift; session_id "$@" ;;
  *) usage ;;
esac
