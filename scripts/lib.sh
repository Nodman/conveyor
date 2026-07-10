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

status_name() { cfg ".status.$1.name"; }
status_id()   { cfg ".status.$1.id"; }
