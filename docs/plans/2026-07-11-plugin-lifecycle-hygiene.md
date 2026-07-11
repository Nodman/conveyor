# Plan: plugin lifecycle hygiene

Spec: docs/specs/2026-07-11-plugin-lifecycle-hygiene.md

**Goal:** plugin ships consent-gated label permissions, the hybrid human-required policy, agent-name comment prefixes, and the self-update rule — one PR.

**Architecture:** `scaffold.sh` gains an opt-in `--grant-label-perms` flag that jq-merges two allow rules into the target repo's `.claude/settings.json`; init/doctor skills own the consent question. Policy and prefix rules are prose in the plugin skills/charters, locked by a structure test. Repo docs record the dogfooding update flow.

**Global constraints (from spec):**
- Allow rules, exactly: `Bash(gh pr edit:*)`, `Bash(gh issue edit:*)` — nothing broader.
- No settings write without the flag; no flag without a user "yes" in the skill flow.
- Prefix format: `**[<agent-name>]**`; orchestrator = `**[team-lead]**`.
- Version bump: `plugin/.claude-plugin/plugin.json` 0.1.0 → 0.1.1 (patch).

## File map

| File | Responsibility |
|---|---|
| plugin/scripts/scaffold.sh | parse flags strictly; step 6 merges allow rules (idempotent, order-preserving, dry-run aware) |
| tests/scaffold.bats | 4 new tests: create, merge/dedupe/preserve, default untouched, dry-run |
| plugin/skills/init/SKILL.md | new consent step between Scaffold and Conflict scan |
| plugin/skills/doctor/SKILL.md | session check: rules missing → finding, ask-first fix |
| plugin/skills/executing-tasks/SKILL.md | executor prefix rule; new "Human-required follow-ups" section |
| plugin/agents/pr-reviewer.md | prefix rule; human-required items in report |
| plugin/agents/qa-agent.md | prefix rule; denied label write → HUMAN-REQUIRED report, never relay |
| tests/structure.bats | markers test locking the prose rules |
| CLAUDE.md (repo, after end marker) | plugin-dev section: version bump + update commands |
| docs/DECISIONS.md | 2026-07-11 rulings entry |
| plugin/.claude-plugin/plugin.json | version 0.1.1 |

## Task 1 — scaffold `--grant-label-perms`

Files: `plugin/scripts/scaffold.sh`, `tests/scaffold.bats`.
Interfaces produced: CLI flag `--grant-label-perms` (combinable with `--dry-run`, any order); unknown flag → `die`.

- [ ] Write failing tests — append to `tests/scaffold.bats`:

```bash
@test "--grant-label-perms creates settings.json with the two allow rules" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.allow | length' "$TMP/.claude/settings.json")" -eq 2 ]
  run jq -r '.permissions.allow[]' "$TMP/.claude/settings.json"
  [[ "$output" == *"Bash(gh pr edit:*)"* ]]
  [[ "$output" == *"Bash(gh issue edit:*)"* ]]
}

@test "--grant-label-perms merges without clobbering, duplicating, or reordering" {
  seed_cfg
  printf '{"permissions":{"allow":["Bash(ls:*)","Bash(gh pr edit:*)"],"deny":["WebFetch"]},"env":{"FOO":"1"}}' \
    > "$TMP/.claude/settings.json"
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --grant-label-perms"
  [ "$status" -eq 0 ]
  [ "$(jq '.permissions.allow | length' "$TMP/.claude/settings.json")" -eq 3 ]
  [ "$(jq -r '.permissions.allow[0]' "$TMP/.claude/settings.json")" = "Bash(ls:*)" ]
  [ "$(jq -r '.permissions.deny[0]' "$TMP/.claude/settings.json")" = "WebFetch" ]
  [ "$(jq -r '.env.FOO' "$TMP/.claude/settings.json")" = "1" ]
}

@test "without --grant-label-perms settings.json is untouched" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh'"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/.claude/settings.json" ]
}

@test "--grant-label-perms respects --dry-run" {
  seed_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/scaffold.sh' --dry-run --grant-label-perms"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -e "$TMP/.claude/settings.json" ]
}
```

- [ ] `bats tests/scaffold.bats` → the 4 new tests fail (flag unknown / file absent).
- [ ] Implement. Replace scaffold.sh:7-8 flag parsing:

```bash
dry=0; grant_perms=0
for a in "$@"; do
  case "$a" in
    --dry-run) dry=1 ;;
    --grant-label-perms) grant_perms=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done
```

  Append step 6 after the CLAUDE.md block step:

```bash
# 6. Label permissions — opt-in only (consent handled by the init/doctor skills).
if [[ $grant_perms -eq 1 ]]; then
  say "grant label permissions in .claude/settings.json"
  if [[ $dry -eq 0 ]]; then
    mkdir -p .claude
    s=.claude/settings.json
    [[ -s "$s" ]] || echo '{}' > "$s"
    tmp=$(mktemp)
    jq '.permissions.allow = ((.permissions.allow // []) +
        (["Bash(gh pr edit:*)","Bash(gh issue edit:*)"] - (.permissions.allow // [])))' \
      "$s" > "$tmp" && mv "$tmp" "$s"
  fi
fi
```

- [ ] `bats tests/scaffold.bats` → all pass; `bats tests` → full suite green; shellcheck clean.
- [ ] Commit: `feat(scaffold): opt-in --grant-label-perms writes lifecycle-label allow rules`

## Task 2 — skill/charter prose + structure test

Files: `plugin/skills/init/SKILL.md`, `plugin/skills/doctor/SKILL.md`, `plugin/skills/executing-tasks/SKILL.md`, `plugin/agents/pr-reviewer.md`, `plugin/agents/qa-agent.md`, `tests/structure.bats`.
Interfaces consumed: the Task-1 flag name, verbatim.

- [ ] Write failing test — append to `tests/structure.bats`:

```bash
@test "prefix rule, human-required policy, and consent gate present in prose" {
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/agents/pr-reviewer.md"
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/agents/qa-agent.md"
  grep -qF -- '**[<agent-name>]**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '**[team-lead]**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '**Human required:**' "$REPO/plugin/skills/executing-tasks/SKILL.md"
  grep -qF -- '--grant-label-perms' "$REPO/plugin/skills/init/SKILL.md"
  grep -qF -- '--grant-label-perms' "$REPO/plugin/skills/doctor/SKILL.md"
}
```

- [ ] `bats tests/structure.bats` → new test fails.
- [ ] Edit prose (exact insertions):

**init/SKILL.md** — insert after step 5 (Scaffold), renumber later steps 6→7, 7→8, 8→9:

```markdown
6. **Label permissions (consent gate).** Conveyor agents apply lifecycle
   labels (`gh pr edit --add-label`); permission classifiers may block that.
   Show the user the exact rules — `Bash(gh pr edit:*)`,
   `Bash(gh issue edit:*)` — the file (`.claude/settings.json`, checked in),
   and why. AskUserQuestion: grant / skip. Yes →
   `scaffold.sh --grant-label-perms`; no → labels stay a manual human step at
   merge time. Never write permissions without this explicit yes.
```

**doctor/SKILL.md** — add bullet to step 2:

```markdown
   - `.claude/settings.json` permissions.allow missing `Bash(gh pr edit:*)`
     or `Bash(gh issue edit:*)` → flag (agents cannot apply lifecycle
     labels). Fix: `scaffold.sh --grant-label-perms` — ask the user first,
     never write permissions silently.
```

**executing-tasks/SKILL.md** —
1. "Per plan task" step 1, extend the executor contract sentence with:
   `Include the comment-prefix rule: every PR/issue comment starts with the
   author's name — `**[<agent-name>]**` (e.g. `**[exec-12-1]** Fixed in
   abc123.`).`
2. New section between "Ship" and "Team hygiene":

```markdown
## Human-required follow-ups

Agents never sit on a human action or relay a denied write to another agent —
they report it; the orchestrator routes it:

- Doable at merge time on that PR (apply a label, run a one-liner) → maintain
  ONE PR comment starting `**[team-lead]** **Human required:**` with a
  checklist; update it in place, never post duplicates.
- Needs scopes/credentials agents lack, or outlives the PR → agent-task
  issue, `card.sh move <n> humanOnly`, `**Unblock:** <exact command>`
  comment, assign the human.
- Chat-only is not tracking: no PR comment or card → it doesn't exist.
```

**pr-reviewer.md** — after the `gh api …/reviews` block note, add:

```markdown
Prefix every comment body you post — review summary, inline findings, thread
replies — with your spawn name: `**[<agent-name>]** …`.
```

and to "Report to the orchestrator": `Human-required items (writes you were
denied, actions needing human scopes) get their own report line — never ask a
peer to perform them.`

**qa-agent.md** — in Verdict, after the Pass line:

```markdown
- Label write denied by permissions → do NOT retry or relay it; report the
  exact command as HUMAN-REQUIRED.
```

and add: `Prefix every PR comment you post with your spawn name:
`**[<agent-name>]** …`.`

- [ ] `bats tests` → full suite green (structure test now passes; no `Nodman`/`PVT_` literals introduced).
- [ ] Commit: `feat(skills,agents): comment prefixes, human-required routing, consent-gated label perms`

## Task 3 — repo docs + version bump

Files: `CLAUDE.md`, `docs/DECISIONS.md`, `plugin/.claude-plugin/plugin.json`.
TDD n/a (docs + version constant). Verification: greps + full suite.

- [ ] Append to `CLAUDE.md` after `<!-- conveyor:end -->`:

```markdown

## Plugin development (this repo dogfoods itself)

- Product source is `plugin/`; live sessions run the installed cache copy —
  source edits do nothing until the plugin is updated.
- Any PR touching `plugin/` bumps the patch version in
  `plugin/.claude-plugin/plugin.json`.
- After merge, a human runs `claude plugin marketplace update
  conveyor-marketplace && claude plugin update conveyor`, then restarts
  sessions that need the new behavior.
```

- [ ] Append to `docs/DECISIONS.md`:

```markdown
## 2026-07-11 — Lifecycle hygiene rulings

- Label permissions: granted only via `scaffold.sh --grant-label-perms` after
  an explicit user yes — consent gate over silent settings writes.
- Human-required follow-ups: hybrid — merge-time actions → one
  `**Human required:**` PR comment; scope/credential or PR-outliving work →
  Human Only card with `**Unblock:**`. Chosen over cards-for-everything to
  keep the board signal high.
- Every agent-authored PR/issue comment carries a `**[<agent-name>]**` prefix.
- Plugin PRs bump the `plugin.json` patch version; consumers pull via
  `claude plugin marketplace update` + `claude plugin update`.
```

- [ ] `plugin/.claude-plugin/plugin.json`: `"version": "0.1.0"` → `"0.1.1"`.
- [ ] Verify: `grep -q 'Plugin development' CLAUDE.md`; `grep -q '2026-07-11' docs/DECISIONS.md`; `jq -r .version plugin/.claude-plugin/plugin.json` = `0.1.1`; `bats tests` green; shellcheck clean.
- [ ] Commit: `docs: plugin-dev flow + lifecycle rulings; bump plugin to 0.1.1`

## Board mapping

Single PR → one agent-task issue ("plugin lifecycle hygiene: label perms, human-required policy, comment prefixes, self-update"), executed via conveyor:executing-tasks. QA note: runtime surface is scaffold.sh only; skills/charters are prose (structure-tested).
