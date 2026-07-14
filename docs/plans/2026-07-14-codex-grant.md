# Plan: codex full-access grant in --grant-auto-merge (#75)

Spec: docs/specs/2026-07-13-codex-grant.md

**Goal:** `scaffold.sh --grant-auto-merge` also writes the codex write-lane
permission rule and autoMode sentence, so full-access codex spawns pass the
auto-mode classifier.

**Architecture:** one new rule + one new sentence inside the existing
`grant_auto` jq write in scaffold.sh; prose updates in the auto skill;
assertions in the two bats files that pin the grant and the skill contract.

**Global constraints:**
- Only `codex-exec.sh run` is granted; other subcommands stay prompt-gated.
- Cache-installed path → version segment wildcarded; any other location
  (repo dogfood) → literal script dir. Match on `*/.claude/plugins/cache/*/scripts`.
- autoMode sentence must contain `danger-full-access` and name environment
  visibility (honest consent).
- Version bump 0.1.25 → 0.1.26.

## File map

- `plugin/scripts/scaffold.sh` — grant_auto block: derive codex rule path,
  add rule + sentence to the jq write.
- `tests/scaffold.bats` — extend 4 existing grant tests (counts change),
  add 1 cache-layout test.
- `plugin/skills/auto/SKILL.md` — step 1 accept text + step 2 grant check.
- `tests/structure.bats` — auto-contract test pins the new accept text.
- `plugin/.claude-plugin/plugin.json` — 0.1.26.

## Task 1 — scaffold grant, test-first

Files: `tests/scaffold.bats`, `plugin/scripts/scaffold.sh`.
Interfaces: produces the codex rule shape
`Bash(<dir>/codex-exec.sh run:*)` consumed by Task 2's skill wording.

- [ ] `tests/scaffold.bats`: update the four existing tests:
  - line ~185 (adds rule test): after the `gh pr merge` assertion add

    ```bash
    [ "$(jq '.permissions.allow | map(select(test("codex-exec.sh run"))) | length' "$s")" -eq 1 ]
    grep -q 'danger-full-access' "$s"
    ```

    and change `.autoMode.allow | length` from `2` to `3`.
  - idempotent test: `.permissions.allow | length` 1 → 2; `.autoMode.allow |
    length` 2 → 3.
  - composes test: `.permissions.allow | length` 5 → 6; `.autoMode.allow |
    length` 3 → 4.
  - preserves test: `.permissions.allow | length` 2 → 3.
- [ ] Append the cache-layout test:

  ```bash
  @test "--grant-auto-merge wildcards the version segment when run from the plugin cache" {
    seed_cfg
    fake="$TMP/fakehome/.claude/plugins/cache/mkt/conveyor/9.9.9"
    mkdir -p "$fake"
    cp -R "$REPO/plugin/scripts" "$REPO/plugin/templates" "$fake/"
    run bash -c "cd '$TMP' && '$fake/scripts/scaffold.sh' --grant-auto-merge"
    [ "$status" -eq 0 ]
    s="$TMP/.claude/settings.json"
    jq -r '.permissions.allow[]' "$s" | grep -qF "conveyor/*/scripts/codex-exec.sh run:*"
  }
  ```

- [ ] `bats tests/scaffold.bats` → the five touched tests FAIL, rest pass.
- [ ] `plugin/scripts/scaffold.sh`: in the `grant_auto` block, before the jq
  call, derive the rule; then extend the jq write:

  ```bash
  scripts_dir="$(cd "$here" && pwd)"
  if [[ "$scripts_dir" == */.claude/plugins/cache/*/scripts ]]; then
    codex_rule="Bash($(dirname "$(dirname "$scripts_dir")")/*/scripts/codex-exec.sh run:*)"
  else
    codex_rule="Bash(${scripts_dir}/codex-exec.sh run:*)"
  fi
  codex_sentence="The user has explicitly pre-authorized conveyor's codex write lane: running codex-exec.sh run with --sandbox danger-full-access inside per-issue worktrees. This grants codex full file and network access (it edits, tests, commits, pushes) and visibility of the local environment. Applies in declared /conveyor:auto runs and in human-gated sessions."
  ```

  jq becomes:

  ```bash
  jq --arg rule "$rule" --arg crule "$codex_rule" --arg csent "$codex_sentence" \
    '.permissions.allow = ((.permissions.allow // []) +
      (["Bash(gh pr merge:*)", $crule] - (.permissions.allow // [])))
    | .autoMode.allow = ((.autoMode.allow // []) +
      (["$defaults", $rule, $csent] - (.autoMode.allow // [])))' \
    "$s" > "$tmp" && mv "$tmp" "$s"
  ```

- [ ] `bats tests/scaffold.bats` → all pass. `shellcheck
  plugin/scripts/scaffold.sh` clean. `bats tests` → all pass.
- [ ] Commit: `feat(scaffold): grant codex write lane in --grant-auto-merge (#75)`

## Task 2 — auto skill wording + version, test-first

Files: `tests/structure.bats`, `plugin/skills/auto/SKILL.md`,
`plugin/.claude-plugin/plugin.json`.
Interfaces: consumes Task 1's rule shape (`codex-exec.sh run` substring in
the step 2 check).

- [ ] `tests/structure.bats`, auto-contract test: after the `'Auto-merge
  step'` assertion (BEFORE the negated last line — bats gotcha) add:

  ```bash
  grep -qF -- 'spawn codex full-access' "$f"
  ```

- [ ] `bats tests/structure.bats` → that test FAILS; rest pass.
- [ ] `plugin/skills/auto/SKILL.md` step 1, replace the accept sentence:

  ```
  old: "I agree — autonomous run: merge PRs, self-approve specs/plans, file and
   triage issues without asking me."
  new: "I agree — autonomous run: merge PRs, self-approve specs/plans, spawn
   codex full-access, file and triage issues without asking me."
  ```

  Step 2, replace the condition sentence:

  ```
  old: If `.claude/settings.json` lacks
   `Bash(gh pr merge:*)` in `permissions.allow` OR lacks the auto-run rule
   in `autoMode.allow`, run
  new: If `.claude/settings.json` lacks
   `Bash(gh pr merge:*)` or a `codex-exec.sh run` rule in
   `permissions.allow`, OR lacks the auto-run rule in `autoMode.allow`, run
  ```

- [ ] `plugin/.claude-plugin/plugin.json`: `"version": "0.1.26"`.
- [ ] `bats tests` → all pass.
- [ ] Commit: `docs(auto): agreement + grant check cover codex full-access; 0.1.26 (#75)`

## Board mapping

Single-PR plan → #75 is the card, already In Progress.
