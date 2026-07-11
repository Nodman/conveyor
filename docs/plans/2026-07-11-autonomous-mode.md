# Plan: autonomous mode (`/conveyor:work auto`)

Spec: `docs/specs/2026-07-11-autonomous-mode.md`.

**Goal.** `/conveyor:work auto` drains the board autonomously — dispatcher +
fresh lead per card, judge-agent spec/plan approval, auto-merge — until Ready
for dev + Backlog are empty or the brake trips.

**Architecture.** Mostly prose: skill/agent markdown whose invariants are
pinned by `tests/structure.bats` greps. The only executable change is
`scaffold.sh --grant-auto-merge` (a `.claude/settings.json` writer mirroring
`--grant-label-perms`). Single PR.

**Global constraints (from the spec):**
- Agreement prompt every auto run; permissions scaffold once per repo.
- Brake: 3 consecutive no-merge cards → stop; merges reset the counter.
- Work sources: Ready for dev + Backlog only; Human Only is write-only.
- Merge: `gh pr merge <n> --squash --delete-branch`; Done stays board
  automation's.
- Judges never edit files; 2 rejections on the same artifact → Human Only.
- Tests: `bats tests` + shellcheck green (running-tests skill; bats runs
  bash 3.2).
- Version: `plugin/.claude-plugin/plugin.json` 0.1.14 → 0.1.15.

## File map

| File | Responsibility |
|---|---|
| `plugin/scripts/scaffold.sh` | new `--grant-auto-merge` flag: merge permission + auto-run autoMode rule |
| `tests/scaffold.bats` | 5 new tests for the flag |
| `tests/structure.bats` | prose invariants: judge agents, work auto section, auto-merge step |
| `plugin/agents/spec-judge.md` | new: spec approval gate charter |
| `plugin/agents/plan-judge.md` | new: plan approval gate charter |
| `plugin/skills/work/SKILL.md` | Auto mode section: agreement gate, dispatcher, triage, brake |
| `plugin/skills/executing-tasks/SKILL.md` | Auto-merge step; human-merge line made mode-conditional |
| `README.md` | Autonomous mode section; tagline + lifecycle step 8 tweaks |
| `plugin/.claude-plugin/plugin.json` | description tweak + version 0.1.15 |

---

## Task 1 — `scaffold.sh --grant-auto-merge`

Files: `plugin/scripts/scaffold.sh`, `tests/scaffold.bats`.
Produces: the flag consumed by the work skill (Task 3) and the settings
entries (`Bash(gh pr merge:*)` in `permissions.allow`; auto-run rule in
`autoMode.allow`).

- [ ] Append to `tests/scaffold.bats`:

```bash
@test "--grant-auto-merge adds the merge allow and the auto-run autoMode rule" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-auto-merge"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | index("Bash(gh pr merge:*)")' "$s")" != "null" ]
  [ "$(jq '.autoMode.allow | length' "$s")" -eq 2 ]
  [ "$(jq -r '.autoMode.allow[0]' "$s")" = '$defaults' ]
  grep -q 'conveyor:work auto' "$s"
  grep -q 'ready-to-merge' "$s"
}

@test "--grant-auto-merge is idempotent — re-run adds no duplicates" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-auto-merge"
  [ "$status" -eq 0 ]
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-auto-merge"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | length' "$s")" -eq 1 ]
  [ "$(jq '.autoMode.allow | length' "$s")" -eq 2 ]
}

@test "--grant-auto-merge composes with --grant-label-perms" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms --grant-auto-merge"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq '.permissions.allow | length' "$s")" -eq 5 ]
  [ "$(jq '.autoMode.allow | length' "$s")" -eq 3 ]
  [ "$(jq -r '.autoMode.allow[0]' "$s")" = '$defaults' ]
}

@test "--grant-auto-merge preserves existing settings" {
  seed_cfg
  printf '{"permissions":{"allow":["Bash(ls:*)"]},"env":{"FOO":"1"}}' \
    > "$TMP/.claude/settings.json"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-auto-merge"
  [ "$status" -eq 0 ]
  s="$TMP/.claude/settings.json"
  [ "$(jq -r '.permissions.allow[0]' "$s")" = "Bash(ls:*)" ]
  [ "$(jq '.permissions.allow | length' "$s")" -eq 2 ]
  [ "$(jq -r '.env.FOO' "$s")" = "1" ]
}

@test "--grant-auto-merge respects --dry-run" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --dry-run --grant-auto-merge"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/.claude/settings.json" ]
  [[ "$output" == *"[dry-run]"* ]]
}
```

- [ ] `bats tests/scaffold.bats` → the 5 new tests fail (`unknown flag`).
- [ ] Implement in `plugin/scripts/scaffold.sh`. Flag parse (line 7-14)
  becomes:

```bash
dry=0; grant_perms=0; grant_auto=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --grant-label-perms) grant_perms=1 ;;
    --grant-auto-merge) grant_auto=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done
```

  New section after the `--grant-label-perms` block:

```bash
# 7. Auto-merge permissions — opt-in only (consent = per-run agreement prompt in the work skill).
if [[ $grant_auto -eq 1 ]]; then
  say "grant auto-merge permissions in .claude/settings.json"
  if [[ $dry -eq 0 ]]; then
    mkdir -p .claude
    s=.claude/settings.json
    [[ -s "$s" ]] || echo '{}' > "$s"
    tmp=$(mktemp)
    rule="During a declared '/conveyor:work auto' run the user has explicitly agreed, via the per-run prompt, to autonomous operation: squash-merging PRs that carry the ready-to-merge label (gh pr merge --squash --delete-branch) and judge-agent self-approval of specs and plans are pre-authorized. Outside a declared auto run, merging PRs stays human-only. Moving cards to Done is never agent-performed — board automation owns it."
    jq --arg rule "$rule" '.permissions.allow = ((.permissions.allow // []) +
        (["Bash(gh pr merge:*)"] - (.permissions.allow // [])))
      | .autoMode.allow = ((.autoMode.allow // []) +
        (["$defaults", $rule] - (.autoMode.allow // [])))' \
      "$s" > "$tmp" && mv "$tmp" "$s"
  fi
fi
```

- [ ] `bats tests/scaffold.bats` → all pass; `shellcheck
  plugin/scripts/scaffold.sh` clean.
- [ ] Commit: `scaffold: --grant-auto-merge permissions flag`

## Task 2 — judge agents

Files: `plugin/agents/spec-judge.md`, `plugin/agents/plan-judge.md`,
`tests/structure.bats`.
Produces: agent names `spec-judge`, `plan-judge` consumed by Task 3's
spec-lead flow. Existing structure tests auto-cover frontmatter +
portability; existing `ready-to-merge` ownership test requires judges never
mention `-label ready-to-merge` — they don't touch labels at all.

- [ ] Append to `tests/structure.bats`:

```bash
@test "judge agents exist, prefix their comments, and never edit" {
  for f in "$REPO/plugin/agents/spec-judge.md" "$REPO/plugin/agents/plan-judge.md"; do
    [ -f "$f" ]
    grep -qF -- 'never edit' "$f"
  done
  grep -qF -- '**[spec-judge]**' "$REPO/plugin/agents/spec-judge.md"
  grep -qF -- '**[plan-judge]**' "$REPO/plugin/agents/plan-judge.md"
}
```

- [ ] `bats tests/structure.bats` → new test fails.
- [ ] Write `plugin/agents/spec-judge.md`:

```markdown
---
name: spec-judge
description: >-
  Approval gate for specs written during autonomous runs — stands in for the
  human at the brainstorming user gate. Give it the spec path + issue number.
  Judges section completeness, placeholders, contradictions, ambiguity, and
  scope-vs-issue. Approve → issue-comment audit trail; reject → findings back
  to the spec-lead. Judges only — never edits files.
model: inherit
---

You are the **spec approval gate** in an autonomous run. You stand in for the
human who normally approves a spec before planning. Be adversarial — a bad
spec approved here wastes the whole downstream pipeline. When the spec is
genuinely sound, approve plainly; never manufacture findings.

Input: spec path (`docs/specs/…`), issue number.

## Judge

1. Read the spec, the issue (acceptance criteria), docs/DECISIONS.md, and
   docs/gotchas/README.md entries touching the spec's area.
2. Reject on any of:
   - missing or empty section (What, Why, Decisions, Design, Out of scope)
   - placeholders: TBD, "handle appropriately", options left open
   - contradictions between sections
   - a requirement readable two ways (state both readings)
   - scope mismatch: spec exceeds or undershoots the issue
   - conflict with a locked ruling in docs/DECISIONS.md
3. Otherwise approve.

## Verdict

- Approve → `gh issue comment <issue> --body "**[spec-judge]** Approved
  <spec path> @ <short sha>."`
- Reject → one issue comment, `**[spec-judge]**` prefix, one bullet per
  finding: `section · defect · why it blocks`.
- Report to the orchestrator: verdict + the same bullets. You never edit any
  file and never move cards.
```

- [ ] Write `plugin/agents/plan-judge.md`:

```markdown
---
name: plan-judge
description: >-
  Approval gate for implementation plans during autonomous runs — stands in
  for the human between writing-plans and execution. Give it the plan path,
  spec path, and issue number. Judges spec coverage, exact paths, real code
  in TDD steps, interface consistency, board mapping. Approve →
  issue-comment audit trail; reject → findings back to the spec-lead. Judges
  only — never edits files.
model: inherit
---

You are the **plan approval gate** in an autonomous run. You stand in for the
human who normally approves a plan before execution. Be adversarial; approve
plainly when the plan is sound — never manufacture findings.

Input: plan path (`docs/plans/…`), spec path, issue number.

## Judge

1. Read the plan, its spec, and the issue.
2. Reject on any of:
   - a spec requirement with no task implementing it
   - vague file references — every task needs exact paths
   - TDD steps without real code (a test described but not written), or
     "TBD" / "similar to task N" placeholders
   - interfaces inconsistent across tasks (names/signatures drift)
   - board mapping missing or slices not PR-sized
3. Otherwise approve.

## Verdict

- Approve → `gh issue comment <issue> --body "**[plan-judge]** Approved
  <plan path> @ <short sha>."`
- Reject → one issue comment, `**[plan-judge]**` prefix, one bullet per
  finding: `task · defect · why it blocks`.
- Report to the orchestrator: verdict + the same bullets. You never edit any
  file and never move cards.
```

- [ ] `bats tests/structure.bats` → all pass.
- [ ] Commit: `agents: spec-judge + plan-judge approval gates`

## Task 3 — work skill: auto mode

Files: `plugin/skills/work/SKILL.md`, `tests/structure.bats`.
Consumes: `--grant-auto-merge` (Task 1), `spec-judge`/`plan-judge` (Task 2).
Produces: the "declared auto run" phrase leads receive, consumed by Task 4.

- [ ] Append to `tests/structure.bats`:

```bash
@test "work skill defines the auto-mode contract" {
  f="$REPO/plugin/skills/work/SKILL.md"
  grep -qF -- 'I agree' "$f"
  grep -qF -- '--grant-auto-merge' "$f"
  grep -qF -- 'never a work source' "$f"
  grep -qF -- '3 consecutive' "$f"
  grep -qF -- 'spec-judge' "$f"
  grep -qF -- 'plan-judge' "$f"
}
```

- [ ] `bats tests/structure.bats` → fails.
- [ ] Append to `plugin/skills/work/SKILL.md`:

```markdown
## Auto mode (`/conveyor:work auto`)

The `auto` argument makes this run autonomous: no human gates until Ready
for dev and Backlog are both empty. Everything below applies to this run
only; a plain `/conveyor:work` afterwards is human-gated again.

1. **Agreement — every run.** AskUserQuestion; the accept option reads: "I
   agree — autonomous run: merge PRs, self-approve specs/plans, file and
   triage issues without asking me." Decline → offer a plain run and stop.
   The agreement in-session is what pre-authorizes the merge writes.
2. **Permissions — once per repo.** If `.claude/settings.json` lacks
   `Bash(gh pr merge:*)` in `permissions.allow`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/scaffold.sh --grant-auto-merge`.
3. **Dispatch loop.** You are the dispatcher: never orchestrate a card
   yourself, keep only per-card reports in context.
   - `/conveyor:doctor` once at start.
   - Pick the top Ready-for-dev card (rules in step 2 above) → spawn a FRESH
     lead subagent for that one card. Give it: the issue number, the
     conveyor:executing-tasks skill by name, the sentence "This is a
     declared `/conveyor:work auto` run — finish with the Auto-merge step",
     and the report contract: one paragraph — `merged <sha>` or
     `blocked: <reason>`, plus issues filed.
   - Judge the report, tally it, release the lead. Merged → brake counter
     resets; anything else → +1.
   - Ready empty → Backlog triage (step 4), then resume the loop.
   - Stop on: Ready + Backlog both empty, or 3 consecutive no-merge cards
     (brake). Final summary: merged / filed / parked / brake state.
4. **Backlog triage.** Spawn a triage agent: read every open Backlog issue,
   classify each `groomed | needs-spec | human` + one-line reason; report
   only the classification. Dispatcher acts:
   - groomed → `card.sh move <n> ready`
   - human → `card.sh move <n> humanOnly` + `**Unblock:**` comment
   - needs-spec → spawn a spec-lead: write the spec (brainstorming skill
     format; decisions come from the issue + docs, no human Q&A) →
     spec-judge gate → conveyor:writing-plans → plan-judge gate → slice to
     Ready cards. A judge rejection gets one fix round; 2 rejections on the
     same artifact → `card.sh move <n> humanOnly` with the draft linked.
5. **Sources.** Work is read ONLY from Ready for dev and Backlog. Human Only
   is write-only parking — never a work source. Never move any card to Done.
```

- [ ] `bats tests/structure.bats` → passes.
- [ ] Commit: `work: auto-mode dispatcher (/conveyor:work auto)`

## Task 4 — executing-tasks: auto-merge step

Files: `plugin/skills/executing-tasks/SKILL.md`, `tests/structure.bats`.
Consumes: the "declared auto run" sentence from Task 3's lead prompt.

- [ ] Append to `tests/structure.bats`:

```bash
@test "executing-tasks defines the auto-merge step" {
  f="$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- 'gh pr merge <n> --squash --delete-branch' "$f"
  grep -qF -- 'gh pr checks' "$f"
  grep -qF -- 'declared auto run' "$f"
}
```

- [ ] `bats tests/structure.bats` → fails.
- [ ] In `plugin/skills/executing-tasks/SKILL.md`, Ship step 5: replace
  `**A human merges. Never merge, never move a card to Done.**` with
  `**Plain runs: a human merges — never merge. Declared auto runs (your
  spawn prompt says so): run the Auto-merge step below. Never move a card
  to Done in any mode.**`
- [ ] Insert a new section after **Ship**:

```markdown
## Auto-merge step (declared auto runs only)

Runs after `ready-to-merge` is applied; every earlier gate is unchanged.

1. Preconditions: `gh pr checks <n>` all green, and no unresolved
   `**Human required:**` checklist on the PR. Either fails → `card.sh move
   <issue> humanOnly` + `**Unblock:**` comment, report `blocked`, stop.
2. Merge conflict → rebase inside the issue worktree (`git -C <path>`,
   docs/gotchas/worktrees.md), push. The push invalidates `qa-passed`
   (rule above) → re-run QA → retry the merge once; second failure →
   humanOnly as in step 1.
3. `gh pr merge <n> --squash --delete-branch`. `Fixes #<issue>` closes the
   issue; board automation moves the card to Done — never move it yourself.
   Then `git worktree remove` the issue worktree and report `merged <sha>`.
```

- [ ] `bats tests/structure.bats` → passes (including the pre-existing
  `ready-to-merge` ownership and worktree-policy tests).
- [ ] Commit: `executing-tasks: auto-merge step for declared auto runs`

## Task 5 — README, plugin.json

Files: `README.md`, `plugin/.claude-plugin/plugin.json`.
TDD n/a (docs + metadata). Verification steps below.

- [ ] README line 4-5 tagline: `… → PR review → QA → human merge** (or
  autonomous merge in a `/conveyor:work auto` run)`.
- [ ] README Lifecycle step 8: append `In an auto run the orchestrator
  merges instead — see Autonomous mode.`
- [ ] README new section after **Lifecycle**:

```markdown
## Autonomous mode

`/conveyor:work auto` drains the board without human gates, for this run only:

- Every run opens with an explicit agreement prompt ("I agree — autonomous
  run: …"); first run also scaffolds `scaffold.sh --grant-auto-merge`
  (adds `Bash(gh pr merge:*)` + an autoMode rule to `.claude/settings.json`).
- Dispatcher pattern: a fresh lead subagent per card runs the full lifecycle
  and squash-merges once CI is green and `ready-to-merge` is applied.
- Ready for dev empty → Backlog triage: groomed issues promoted, feature-sized
  ones spec'd and planned with **spec-judge** / **plan-judge** approval gates
  (2 rejections → Human Only), human-needed ones parked in Human Only.
- Human Only is never a work source. Cards are never moved to Done by agents.
- Brake: 3 consecutive cards without a merge → the run stops and reports.
```

- [ ] `plugin/.claude-plugin/plugin.json`: version `0.1.15`; description →
  `GitHub Projects agent delivery pipeline: brainstorm → spec → plan → TDD
  execution → PR review → QA → human merge (autonomous merge opt-in via
  /conveyor:work auto).`
- [ ] Verify: `jq -r .version plugin/.claude-plugin/plugin.json` → `0.1.15`;
  `bats tests` full suite green; `shellcheck plugin/scripts/*.sh
  plugin/hooks/*.sh tests/helpers/bin/gh tests/helpers/bin/git
  tests/live-smoke.sh` clean.
- [ ] Commit: `docs: autonomous mode; version 0.1.15`

## Board mapping

Single-PR plan → straight to conveyor:executing-tasks.
