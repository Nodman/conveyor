setup() {
  TMP="$(mktemp -d)"
  export TMP
  export GH_LOG="$TMP/gh.log"; : > "$GH_LOG"
  export RUN_LOG="$TMP/run.log"; : > "$RUN_LOG"
  export GH_FIX="${GH_FIX:-$BATS_TEST_DIRNAME/fixtures}"
  export SCRIPTS="$BATS_TEST_DIRNAME/../plugin/scripts"
  export PATH="$BATS_TEST_DIRNAME/helpers/bin:$PATH"
  mkdir -p "$TMP/.claude"
}

teardown() {
  # background --visibility runners are detached (nohup); kill any still referencing
  # this test's TMP so they can't write into it while rm -rf runs (CI teardown race)
  [[ -n "${TMP:-}" ]] && pkill -f "$TMP" 2>/dev/null || true
  rm -rf "$TMP"
}
