#!/usr/bin/env bash
set -euo pipefail

CONVEYOR_CONFIG="${CONVEYOR_CONFIG:-.claude/conveyor.json}"

die() { echo "conveyor: $*" >&2; exit 1; }

die_code3() { echo "conveyor: $*" >&2; exit 3; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"; }

cfg() {
  [[ -f "$CONVEYOR_CONFIG" ]] || die "no $CONVEYOR_CONFIG — run /conveyor:init first"
  jq -er "$1" "$CONVEYOR_CONFIG" || die "config key not found: $1"
}

cfg_or() { # $1=jq filter $2=fallback — like cfg but yields $2 when the key is absent/null
  [[ -f "$CONVEYOR_CONFIG" ]] || die "no $CONVEYOR_CONFIG — run /conveyor:init first"
  local v; v="$(jq -r "$1 // empty" "$CONVEYOR_CONFIG")"
  if [[ -n "$v" ]]; then printf '%s\n' "$v"; else printf '%s\n' "$2"; fi
}

status_name() { cfg ".status.$1.name"; }
status_id()   { cfg ".status.$1.id"; }

warn_capped() { # $1=count $2=limit $3=what — WARN to stderr when a --limit cap is hit
  if [[ "$1" -eq "$2" ]]; then
    echo "WARN: $3 returned $1 == limit — results may be truncated" >&2
  fi
}
