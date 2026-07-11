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

teardown() { rm -rf "$TMP"; }
