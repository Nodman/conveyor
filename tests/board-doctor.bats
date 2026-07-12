#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }

run_doctor() { # $1 = fixture set name
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/$1" \
    run bash -c "cd '$TMP' && '$SCRIPTS/board-doctor.sh'"
}

# ---- clean ----------------------------------------------------------------

@test "clean board reports no drift and exits 0" {
  use_cfg
  run_doctor doctor-clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"no drift (3 issue cards checked)"* ]]
}

# ---- doctor-drift: R1, R2, R6, R7, R8 -------------------------------------

setup_drift() { use_cfg; printf '<!-- conveyor:begin -->\n' > "$TMP/CLAUDE.md"; }

@test "drift set exits 1" {
  setup_drift
  run_doctor doctor-drift
  [ "$status" -eq 1 ]
}

@test "R1 open issue in Done" {
  setup_drift
  run_doctor doctor-drift
  [[ "$output" == *"#20 is OPEN but sits in Done"* ]]
}

@test "R2 closed issue in Backlog" {
  setup_drift
  run_doctor doctor-drift
  [[ "$output" == *"#21 is CLOSED but sits in Backlog"* ]]
}

@test "R6 Human Only without Unblock comment" {
  setup_drift
  run_doctor doctor-drift
  [[ "$output" == *"#22 in Human Only has no Unblock: comment"* ]]
}

@test "R7 stale config status option id" {
  setup_drift
  run_doctor doctor-drift
  [[ "$output" == *"config status 'archived' id opt_av absent from live board"* ]]
}

@test "R8 broken CLAUDE.md marker block" {
  setup_drift
  run_doctor doctor-drift
  [[ "$output" == *"CLAUDE.md conveyor marker block is broken"* ]]
}

# ---- R6/R7 API-failure robustness -----------------------------------------

@test "R6 unblock-comment check failure WARNs, does not flag, exits 0" {
  use_cfg
  run_doctor doctor-r6-viewfail
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: #50 unblock-comment check failed — re-run"* && "$output" != *"in Human Only has no Unblock: comment"* ]]
}

@test "R7 config staleness check failure WARNs and exits 0" {
  use_cfg
  run_doctor doctor-r7-discoverfail
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: config staleness check failed — re-run"* ]]
}

@test "R7 live board with no Priority field flags and exits 1" {
  use_cfg
  run_doctor doctor-noprio
  [ "$status" -eq 1 ]
  [[ "$output" == *"live board has no Priority field"* ]]
}

@test "R7 config with no priority mapping flags and exits 1" {
  jq '.priority = null' "$BATS_TEST_DIRNAME/fixtures/conveyor.json" > "$TMP/.claude/conveyor.json"
  GH_FIX="$BATS_TEST_DIRNAME/fixtures/doctor-clean" \
    run --separate-stderr bash -c "cd '$TMP' && '$SCRIPTS/board-doctor.sh'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"config has no priority mapping"* && "$stderr" != *"has no keys"* ]]
}

# ---- doctor-drift-pr: R3, R5 (no PR) --------------------------------------

@test "pr set exits 1" {
  use_cfg
  run_doctor doctor-drift-pr
  [ "$status" -eq 1 ]
}

@test "R3 Agent Review with no open PR" {
  use_cfg
  run_doctor doctor-drift-pr
  [[ "$output" == *"#30 in Agent Review has no open PR closing it"* ]]
}

@test "R5 QA with no open PR" {
  use_cfg
  run_doctor doctor-drift-pr
  [[ "$output" == *"#31 in QA has no open PR closing it"* ]]
}

# ---- doctor-drift-qa: R4, R5 (unapproved PR) ------------------------------

@test "qa set exits 1" {
  use_cfg
  run_doctor doctor-drift-qa
  [ "$status" -eq 1 ]
}

@test "R4 In Progress with an open PR" {
  use_cfg
  run_doctor doctor-drift-qa
  [[ "$output" == *"#40 in In Progress has an open PR"* ]]
}

@test "R5 QA open PR without approved label" {
  use_cfg
  run_doctor doctor-drift-qa
  [[ "$output" == *"#41 in QA has an open PR but none carries the approved label"* ]]
}

# ---- doctor-drift-labels: R9 (missing configured label) -------------------

@test "labels set exits 1" {
  use_cfg
  run_doctor doctor-drift-labels
  [ "$status" -eq 1 ]
}

@test "R9 missing configured label with fix command" {
  use_cfg
  run_doctor doctor-drift-labels
  [[ "$output" == *"label 'qa-passed' missing"* && "$output" == *"gh label create 'qa-passed' --force -R acme/widget"* ]]
}

@test "R9 missing ready-to-merge label with fix command" {
  use_cfg
  run_doctor doctor-drift-labels
  [[ "$output" == *"label 'ready-to-merge' missing"* && "$output" == *"gh label create 'ready-to-merge' --force -R acme/widget"* ]]
}

@test "pre-0.1.13 config (no readyToMerge) — doctor runs all rules and flags the missing config key" {
  cp "$BATS_TEST_DIRNAME/fixtures/conveyor-pre-readytomerge.json" "$TMP/.claude/conveyor.json"
  run_doctor doctor-clean
  [ "$status" -eq 1 ]
  [[ "$output" != *"config key not found"* && "$output" == *"config .labels.readyToMerge missing"* ]]
}

# ---- R10: orphaned worktrees ----------------------------------------------

@test "R10 worktree with no open PR WARNs and still exits 0" {
  use_cfg
  run_doctor doctor-worktree-orphan
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphaned worktree"* && "$output" == *"fix/9-stale"* ]]
}

@test "R10 worktree with an open PR is not flagged" {
  use_cfg
  run_doctor doctor-worktree-active
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphaned worktree"* ]]
}

@test "R10 skips the main checkout and agent-* worktrees" {
  use_cfg
  run_doctor doctor-worktree-orphan
  [[ "$output" != *"agent-tmp"* ]]
}

@test "R10 handles worktree paths containing spaces" {
  use_cfg
  run_doctor doctor-worktree-space
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphaned worktree /repo/.claude/worktrees/fix-9 spaced"* ]]
}

# ---- pluginVersion stamp ---------------------------------------------------

@test "clean run stamps pluginVersion and preserves other keys" {
  use_cfg
  before_owner="$(jq -r .owner "$TMP/.claude/conveyor.json")"
  run_doctor doctor-clean
  [ "$status" -eq 0 ]
  v="$(jq -r .version "$BATS_TEST_DIRNAME/../plugin/.claude-plugin/plugin.json")"
  [ "$(jq -r .pluginVersion "$TMP/.claude/conveyor.json")" = "$v" ]
  [ "$(jq -r .owner "$TMP/.claude/conveyor.json")" = "$before_owner" ]
}

@test "clean run reports stamp and commit reminder" {
  use_cfg
  run_doctor doctor-clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"stamped pluginVersion"* ]]
  [[ "$output" == *"commit .claude/conveyor.json"* ]]
}

@test "drift run still stamps pluginVersion" {
  setup_drift
  run_doctor doctor-drift
  [ "$status" -eq 1 ]
  v="$(jq -r .version "$BATS_TEST_DIRNAME/../plugin/.claude-plugin/plugin.json")"
  [ "$(jq -r .pluginVersion "$TMP/.claude/conveyor.json")" = "$v" ]
}

@test "newer stamp than installed → never downgraded" {
  use_cfg
  jq '.pluginVersion = "999.0.0"' "$TMP/.claude/conveyor.json" > "$TMP/cfg.tmp" && mv "$TMP/cfg.tmp" "$TMP/.claude/conveyor.json"
  run_doctor doctor-clean
  [ "$status" -eq 0 ]
  [ "$(jq -r .pluginVersion "$TMP/.claude/conveyor.json")" = "999.0.0" ]
  [[ "$output" != *"stamped pluginVersion"* ]]
}

# ---- list truncation WARNs (issue #4) -------------------------------------

mk_capped() { # $1=dest dir  $2=item count  $3=issue count — clean board, capped lists
  cp -r "$BATS_TEST_DIRNAME/fixtures/doctor-clean" "$1"
  jq -n --argjson c "$2" \
    '{items: [range($c) | {id: "PVTI_\(1000+.)", content: {number: (1000+.), type: "Issue"}, status: "Done"}]}' \
    > "$1/project_item-list.out"
  jq -n --argjson c "$3" '[range($c) | {number: (2000+.)}]' > "$1/issue_list.out"
}

@test "item-list at the 200 cap WARNs and still exits 0 on a clean board" {
  use_cfg
  mk_capped "$TMP/fix" 200 5
  GH_FIX="$TMP/fix" run bash -c "cd '$TMP' && '$SCRIPTS/board-doctor.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: gh project item-list returned 200 == limit — results may be truncated"* ]]
}

@test "issue list at the 300 cap WARNs and still exits 0 on a clean board" {
  use_cfg
  mk_capped "$TMP/fix" 5 300
  GH_FIX="$TMP/fix" run bash -c "cd '$TMP' && '$SCRIPTS/board-doctor.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: gh issue list returned 300 == limit — results may be truncated"* ]]
}

@test "counts below the caps emit no truncation WARN" {
  use_cfg
  mk_capped "$TMP/fix" 199 299
  GH_FIX="$TMP/fix" run bash -c "cd '$TMP' && '$SCRIPTS/board-doctor.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"== limit — results may be truncated"* ]]
}
