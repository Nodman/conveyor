# GitHub API

## Projects item-list lags item-add
Symptom: a card added via `gh project item-add` is missing from an immediate `gh project item-list` (doctor counted 5 of 6).
Cause: ProjectsV2 reads are eventually consistent — list can trail writes by a second or two.
Rule: never assert board state in the same breath as a mutation; re-query (or sleep ~2s) before doctor/verification runs.

## PR review post with abbreviated commit_id fails silently
Symptom: review gate reports "verdict posted" but the PR has no review; downstream automation proceeds on it (cooqa-swift #214, 2026-07-15).
Cause: `gh api repos/{owner}/{repo}/pulls/<n>/reviews -f commit_id=<sha>` 422s (`Variable $commitOID of type GitObjectID was provided invalid value`) on an abbreviated SHA — it needs the full 40-char OID. Agents filtering output for the success URL never see the error.
Rule: always pass the full SHA (`git rev-parse HEAD` or `gh pr view --json headRefOid`); after posting, re-list the PR reviews and confirm the new review exists before reporting success.
