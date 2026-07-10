#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

file="${1:-}"
[[ -n "$file" ]] || die "usage: claude-block.sh FILE < content"

begin='<!-- conveyor:begin -->'
end='<!-- conveyor:end -->'
content="$(cat)"

if [[ ! -e "$file" ]]; then
  { printf '%s\n' "$begin"; printf '%s\n' "$content"; printf '%s\n' "$end"; } > "$file"
  exit 0
fi

bcount="$(grep -Fxc "$begin" "$file" || true)"
ecount="$(grep -Fxc "$end" "$file" || true)"

if [[ "$bcount" -eq 0 && "$ecount" -eq 0 ]]; then
  { printf '\n%s\n' "$begin"; printf '%s\n' "$content"; printf '%s\n' "$end"; } >> "$file"
  exit 0
fi

[[ "$bcount" -eq 1 && "$ecount" -eq 1 ]] \
  || die "broken markers in $file (begin=$bcount end=$ecount) — expected exactly one of each"

bline="$(grep -Fxn "$begin" "$file" | head -1 | cut -d: -f1)"
eline="$(grep -Fxn "$end" "$file" | head -1 | cut -d: -f1)"

tmp="$(mktemp)"
{
  head -n "$bline" "$file"
  printf '%s\n' "$content"
  tail -n "+$eline" "$file"
} > "$tmp"
mv "$tmp" "$file"
