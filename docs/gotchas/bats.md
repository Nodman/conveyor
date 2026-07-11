# Bats

## Mid-test `[[ ]]` assertion failures do not fail the test
Symptom: a bats test passes even though an earlier `[[ … ]]` assertion is false (verified on bats 1.13: failing `[[ ]]` mid-test → ok; failing `[ ]` mid-test → not ok).
Cause: bats' errexit tracking doesn't trip on `[[ ]]` returning non-zero unless it is the test's last command.
Rule: a test's ONLY gating assertion is its last command — put the decisive `[[ ]]` last, or use `[ ]` for every mid-test assertion.
