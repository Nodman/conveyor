---
name: running-tests
description: Use when you need to run the conveyor test suite — the green gate for any script/hook/harness change.
---

# Running the conveyor tests

- `bats tests` from the repo root — the full suite (offline, stubbed gh).
- `shellcheck plugin/scripts/*.sh plugin/hooks/*.sh tests/helpers/bin/gh tests/helpers/bin/git tests/live-smoke.sh` — must be clean; CI runs both.
- Green = zero failures; report real counts.

Traps:
- bats runs macOS system bash 3.2: no negative array subscripts, no mapfile;
  heredocs inside `$( )` mis-parse apostrophes — use `read -r -d '' … || true`.
- The gh stub matches `api graphql` fixtures by op-name substring and persists
  `--input -` bodies to `$TMP/last-graphql.json` — assert payloads there.
