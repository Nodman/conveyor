# GitHub API

## Projects item-list lags item-add
Symptom: a card added via `gh project item-add` is missing from an immediate `gh project item-list` (doctor counted 5 of 6).
Cause: ProjectsV2 reads are eventually consistent — list can trail writes by a second or two.
Rule: never assert board state in the same breath as a mutation; re-query (or sleep ~2s) before doctor/verification runs.
