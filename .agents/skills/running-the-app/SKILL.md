---
name: running-the-app
description: Use when you need to exercise conveyor end-to-end — QA verification of scripts/skills against real GitHub, or checking the plugin installs and loads.
---

# Running conveyor (the "app" is the plugin)

- **Offline first**: `bats tests` + shellcheck (running-tests skill) cover most behavior.
- **End-to-end against real GitHub**: `RUN_LIVE=1 tests/live-smoke.sh` — creates
  a scratch repo + board under the authenticated account, runs
  create → discover → scaffold → doctor → reconcile round-trip, tears down.
  Needs `gh` scopes `repo` + `project`; repo teardown also needs `delete_repo`
  (without it the smoke prints the manual cleanup command — hand it to the human).
- **Plugin install check**: `claude plugin uninstall conveyor@conveyor-marketplace
  && claude plugin install conveyor@conveyor-marketplace`, then verify the cache
  root contains agents/hooks/scripts/skills/templates (the `plugin/` subdir is
  the shipped root via marketplace `source: "./plugin"`). Skills/hooks load on
  the NEXT session start, not the current one.
- **Single scripts**: run directly from `plugin/scripts/` in a scratch dir with
  a hand-written `.claude/conveyor.json` — they read config from cwd.
