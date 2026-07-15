# Bats

## Mid-test `[[ ]]` assertion failures do not fail the test
Symptom: a bats test passes even though an earlier `[[ … ]]` assertion is false (verified on bats 1.13: failing `[[ ]]` mid-test → ok; failing `[ ]` mid-test → not ok).
Cause: bats' errexit tracking doesn't trip on `[[ ]]` returning non-zero unless it is the test's last command.
Rule: a test's ONLY gating assertion is its last command — put the decisive `[[ ]]` last, or use `[ ]` for every mid-test assertion.

## Clearing `TMUX` alone still leaks the host pane target
Symptom: a test intended to exercise the non-tmux fallback unexpectedly targets the developer's live pane.
Cause: tmux exports `TMUX_PANE` separately, and `env -u TMUX` leaves it intact.
Rule: terminal-isolated tests must unset both `TMUX` and `TMUX_PANE`.
