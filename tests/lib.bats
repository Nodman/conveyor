#!/usr/bin/env bats
load helpers/env

use_cfg() { cp "$BATS_TEST_DIRNAME/fixtures/conveyor.json" "$TMP/.claude/conveyor.json"; }

@test "cfg reads values from config" {
  use_cfg
  run bash -c "cd '$TMP' && source '$SCRIPTS/lib.sh' && cfg .owner"
  [ "$output" = "acme" ]
}

@test "cfg dies without config file" {
  run bash -c "cd '$TMP' && source '$SCRIPTS/lib.sh' && cfg .owner"
  [ "$status" -eq 1 ]
  [[ "$output" == *"conveyor:init"* ]]
}

@test "status_name and status_id resolve canonical keys" {
  use_cfg
  run bash -c "cd '$TMP' && source '$SCRIPTS/lib.sh' && status_name agentReview && status_id qa"
  [ "${lines[0]}" = "Agent Review" ]
  [ "${lines[1]}" = "opt_qa" ]
}

@test "die_code3 exits with code 3" {
  run bash -c "source '$SCRIPTS/lib.sh' && die_code3 no card found"
  [ "$status" -eq 3 ]
  [[ "$output" == *"conveyor: no card found"* ]]
}
