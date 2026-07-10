#!/usr/bin/env bats
load helpers/env

@test "missing file → created with only the block" {
  f="$TMP/CLAUDE.md"
  printf 'A\nB\n' | "$SCRIPTS/claude-block.sh" "$f"
  printf '<!-- conveyor:begin -->\nA\nB\n<!-- conveyor:end -->\n' > "$TMP/exp"
  run cmp "$f" "$TMP/exp"
  [ "$status" -eq 0 ]
}

@test "existing file without markers → block appended after a blank line" {
  f="$TMP/CLAUDE.md"
  printf 'top\n' > "$f"
  printf 'X\n' | "$SCRIPTS/claude-block.sh" "$f"
  printf 'top\n\n<!-- conveyor:begin -->\nX\n<!-- conveyor:end -->\n' > "$TMP/exp"
  run cmp "$f" "$TMP/exp"
  [ "$status" -eq 0 ]
}

@test "both markers → only lines between are replaced, rest byte-for-byte" {
  f="$TMP/CLAUDE.md"
  printf 'head\n<!-- conveyor:begin -->\nOLD1\nOLD2\n<!-- conveyor:end -->\ntail\n' > "$f"
  printf 'NEW1\nNEW2\n' | "$SCRIPTS/claude-block.sh" "$f"
  printf 'head\n<!-- conveyor:begin -->\nNEW1\nNEW2\n<!-- conveyor:end -->\ntail\n' > "$TMP/exp"
  run cmp "$f" "$TMP/exp"
  [ "$status" -eq 0 ]
}

@test "begin marker only → exit 1, message, file untouched" {
  f="$TMP/CLAUDE.md"
  printf 'a\n<!-- conveyor:begin -->\nb\n' > "$f"
  cp "$f" "$TMP/before"
  run bash -c "printf 'Z\n' | '$SCRIPTS/claude-block.sh' '$f'"
  [ "$status" -eq 1 ]
  [[ "$output" == *marker* ]]
  run cmp "$f" "$TMP/before"
  [ "$status" -eq 0 ]
}

@test "end marker only → exit 1, message, file untouched" {
  f="$TMP/CLAUDE.md"
  printf 'a\n<!-- conveyor:end -->\nb\n' > "$f"
  cp "$f" "$TMP/before"
  run bash -c "printf 'Z\n' | '$SCRIPTS/claude-block.sh' '$f'"
  [ "$status" -eq 1 ]
  [[ "$output" == *marker* ]]
  run cmp "$f" "$TMP/before"
  [ "$status" -eq 0 ]
}

@test "idempotent: create then re-run with same stdin → identical file" {
  f="$TMP/CLAUDE.md"
  printf 'A\nB\n' | "$SCRIPTS/claude-block.sh" "$f"
  cp "$f" "$TMP/after1"
  printf 'A\nB\n' | "$SCRIPTS/claude-block.sh" "$f"
  run cmp "$f" "$TMP/after1"
  [ "$status" -eq 0 ]
}

@test "idempotent: append then re-run with same stdin → identical file" {
  f="$TMP/CLAUDE.md"
  printf 'top\n' > "$f"
  printf 'X\n' | "$SCRIPTS/claude-block.sh" "$f"
  cp "$f" "$TMP/after1"
  printf 'X\n' | "$SCRIPTS/claude-block.sh" "$f"
  run cmp "$f" "$TMP/after1"
  [ "$status" -eq 0 ]
}

@test "missing FILE arg → usage error" {
  run bash -c "printf 'x\n' | '$SCRIPTS/claude-block.sh'"
  [ "$status" -ne 0 ]
  [[ "$output" == *usage* ]]
}
