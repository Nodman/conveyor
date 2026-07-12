# Plan: codex write-mode implementer + advisory reviewer

Spec: `docs/specs/2026-07-12-codex-implementer.md` (Decisions locked).
Issue: #55. Depends on merged #54 (routing skill exists at
`plugin/skills/routing/`).

**Goal:** conveyor consumes the routing skill — codex implements clear-spec
tasks in write mode inside the issue worktree, gives advisory cross-family
reviews, and executor naming switches to the routing scheme.

**Architecture:** `codex-exec.sh` gains `--sandbox` and `--workdir`; the
generated runner cd's into the worktree so write-mode edits land there in
every visibility mode. executing-tasks and pr-reviewer skill prose route
spawns via `plugin/skills/routing/SKILL.md`. Live verification of the new
codex arg shapes happens once, recorded in gotchas.

**Global constraints (locked):**
- Fresh run sandbox: `-s <mode>`; resume: `-c 'sandbox_mode="<mode>"'` —
  `resume` REJECTS `-s` (docs/gotchas/codex.md). Default stays `read-only`.
- Sentinel carries the exit code — never a bare touch.
- Mocks must reject what the real CLI rejects; live-verify each new arg
  shape once (docs/gotchas/codex.md).
- Naming: `<runner>-<model>--<issue>-<n>`; no dots in claude Agent names.
- Codex reviews ADVISORY only; claude gate posts everything.
- Orchestrator keeps push/PR/labels/board; codex never pushes.
- bats decisive assertion last (docs/gotchas/bats.md). `bats tests/` green.
- PR touches `plugin/` → version 0.1.17 → 0.1.18.

## File map

| File | Responsibility |
|---|---|
| `plugin/scripts/codex-exec.sh` (modify) | `--sandbox read-only\|workspace-write` + `--workdir <dir>` on `run` |
| `tests/codex-exec.bats` (modify) | new arg-shape tests |
| `docs/gotchas/codex.md` (modify) | live-verified write-mode results |
| `plugin/skills/executing-tasks/SKILL.md` (modify) | routing consumption, codex write lane, new naming |
| `plugin/agents/pr-reviewer.md` (modify) | routing-based model choice + independence rule |
| `plugin/.claude-plugin/plugin.json` (modify) | version 0.1.18 |

## Task 1 — codex-exec.sh: --sandbox + --workdir (TDD)

Files: `plugin/scripts/codex-exec.sh`, `tests/codex-exec.bats`.
Interfaces produced: `run … [--sandbox read-only|workspace-write]
[--workdir <dir>]` — consumed by tasks 2-3.

- [ ] Write failing bats tests (append to tests/codex-exec.bats):

```bats
@test "run --sandbox workspace-write: fresh uses -s workspace-write" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol--55-1 --model gpt-5.6-sol --out '$TMP/w1.md' --prompt-file '$TMP/p.txt' --sandbox workspace-write"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w1.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s workspace-write"* ]]
}

@test "run --sandbox workspace-write resume: -c sandbox_mode, never -s" {
  use_cfg
  printf 'fix\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol--55-1 --model gpt-5.6-sol --out '$TMP/w2.md' --prompt-file '$TMP/p.txt' --resume 0000-mock-session --sandbox workspace-write"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w2.md.done"
  run cat "$TMP/w2.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'sandbox_mode="workspace-write"'* && "$output" != *'-s workspace-write'* ]]
}

@test "run --sandbox bogus value → usage" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/x.md' --prompt-file '$TMP/p.txt' --sandbox sometimes"
  [ "$status" -eq 2 ]
}

@test "run --workdir: runner cds there before codex" {
  use_cfg
  mkdir "$TMP/wt"
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w3.md' --prompt-file '$TMP/p.txt' --workdir '$TMP/wt'"
  [ "$status" -eq 0 ]
  wait_sentinel "$TMP/w3.md.done"
  run cat "$TMP/w3.run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cd $TMP/wt"* ]]
}

@test "run --workdir missing dir → dies at spawn" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w4.md' --prompt-file '$TMP/p.txt' --workdir '$TMP/nope'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no workdir"* ]]
}

@test "run default sandbox unchanged: read-only" {
  use_cfg
  printf 'q\n' > "$TMP/p.txt"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name n --model m --out '$TMP/w5.md' --prompt-file '$TMP/p.txt'"
  wait_sentinel "$TMP/w5.md.done"
  run grep -F 'codex exec' "$RUN_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-s read-only"* ]]
}
```

- [ ] Run `bats tests/codex-exec.bats` → the new tests FAIL (unknown args hit
  `*) usage`).
- [ ] Implement in `run_codex` (surgical):
  - init: `local … sandbox_mode="read-only" workdir=""`
  - arg loop adds:
    `--sandbox) sandbox_mode="$2"; shift 2 ;;` and
    `--workdir) workdir="$2"; shift 2 ;;`
  - after required-args check:
    `case "$sandbox_mode" in read-only|workspace-write) ;; *) usage ;; esac`
    and `[[ -z "$workdir" || -d "$workdir" ]] || die "no workdir: $workdir"`
  - command build (replaces the hardcoded lines):
    `local codex_cmd="codex exec -m $model" sandbox="-s $sandbox_mode"` and in
    the resume branch `sandbox="-c 'sandbox_mode=\"$sandbox_mode\"'"`.
  - runner heredoc: after the `echo "=== $name ==="` line, when `workdir` is
    set emit `cd $workdir || { echo 1 > $sentinel; exit 1; }` (sentinel still
    signals failure if the dir vanished between spawn and run).
  - extend the space check: `case "$out$prompt_file$workdir" in *" "*) …`.
  - usage line for `run` gains `[--sandbox read-only|workspace-write]
    [--workdir <dir>]`.
- [ ] `bats tests/codex-exec.bats` → all pass; `bats tests/` → full suite
  green; `shellcheck plugin/scripts/codex-exec.sh` clean.
- [ ] Commit: `codex-exec: --sandbox and --workdir for write-mode runs`

## Task 2 — live-verify write shapes, record in gotchas

Files: `docs/gotchas/codex.md`. Needs real codex CLI (installed + authed,
0.144.1) — NO mocks. TDD n/a (verification task by nature).

- [ ] Scratch repo: `mkdir <scratchpad>/cxwt && git -C <scratchpad>/cxwt init
  -q && git -C <scratchpad>/cxwt commit -q --allow-empty -m init`
- [ ] Fresh write run: prompt file = "Create hello.txt containing 'hi'. Then
  run: git add hello.txt && git commit -m 'add hello'. Report what you did."
  `codex-exec.sh run --name codex-gpt-5.6-sol--55-live --model gpt-5.6-sol
  --out <scratchpad>/live1.md --prompt-file <f> --sandbox workspace-write
  --workdir <scratchpad>/cxwt --visibility background`; poll sentinel.
  Verify: sentinel content `0`; `hello.txt` exists; `git -C … log --oneline`
  shows the commit; note the commit author codex used.
- [ ] Resume write run: session id from live1.log; prompt "Append 'bye' to
  hello.txt and commit as 'update hello'."; same command shape +
  `--resume <sid>`. Verify second commit exists.
- [ ] Network probe (same fresh-run prompt, one line): ask codex to run
  `gh --version && git ls-remote https://github.com/Nodman/conveyor HEAD`
  and report whether they succeeded — records whether write-mode sandbox
  allows network/gh (spec risk: if blocked, "implement+self-test" degrades
  to "implement, claude verifies").
- [ ] Append results to `docs/gotchas/codex.md` as a new section
  `## workspace-write live results (codex-cli <version>, YYYY-MM-DD)`:
  what worked (write, commit, resume-with-write), commit-author shape,
  network/gh verdict. Facts only, condensed.
- [ ] Findings that contradict task 1's implementation → fix codex-exec.sh
  in THIS task (with a bats test mirroring the real behavior, per the
  arg-agnostic-mocks gotcha).
- [ ] `bats tests/` green.
- [ ] Commit: `gotchas: codex workspace-write live-verified`

## Task 3 — executing-tasks consumes routing

Files: `plugin/skills/executing-tasks/SKILL.md`. TDD n/a (skill prose);
verification = section checklist below. Surgical edits only.

- [ ] "Per plan task" step 1: replace the naming sentence
  ("Name executors stably (`exec-<issue>-<n>`) …") and the example
  `**[exec-12-1]**` with:
  - Load `plugin/skills/routing/SKILL.md` first; pick the model per its
    procedure; record the route (class, floor, model, reason) in the spawn
    prompt.
  - Names: `<runner>-<model>--<issue>-<n>` (e.g. `claude-opus-4-8--12-1`,
    `codex-gpt-5.6-sol--12-1`); claude Agent names never contain dots;
    ALWAYS set `model:` explicitly. Example prefix becomes
    `**[claude-opus-4-8--12-1]** Fixed in abc123.`
- [ ] Same step, add the codex lane (new paragraph after the claude-spawn
  contract):
  - Route = codex → `${CLAUDE_PLUGIN_ROOT}/scripts/codex-exec.sh run
    --sandbox workspace-write --workdir <issue worktree> --name
    codex-<model>--<issue>-<n> --model <model> --out <report> --prompt-file
    <f>`; prompt file carries the task text verbatim, output bar, report
    contract, comment-prefix rule, style rule. Wait on the sentinel
    (explicit timeout + poll). Codex edits files and runs LOCAL tests in the
    worktree — it CANNOT commit, push, or reach the network (protected
    `.git`, no DNS; docs/gotchas/codex.md workspace-write live results).
    After the sentinel: the orchestrator judges the diff, reruns the tests
    when codex couldn't, and commits under its own identity.
  - Fix rounds resume by session id (`codex-exec.sh session-id <log>`), one
    targeted repair max, then escalate per routing.
  - One write-mode codex per worktree at a time.
  - Codex missing/throttled → routing fallback (Opus) + ledger note. Tests
    needing network can't run in the sandbox → the diff is unverified until
    the orchestrator runs them.
- [ ] Ship step 2, after the pr-reviewer spawn sentence, add: routing may
  add an ADVISORY cross-family pass — claude-authored code-heavy diff →
  codex read-only review (`--sandbox read-only`) into a findings file; hand
  the file to pr-reviewer, which verifies each finding and does all posting.
  Codex-authored PRs → claude gate alone. Advisory findings never post
  directly.
- [ ] Verify: diff touches only the listed spots; naming example consistent
  with `plugin/skills/routing/references/delegation-contract.md`;
  `bats tests/` green (test 118 re-parses skill frontmatter).
- [ ] Commit: `executing-tasks: route spawns via routing skill; codex write lane`

## Task 4 — pr-reviewer routing prose + version bump

Files: `plugin/agents/pr-reviewer.md`, `plugin/.claude-plugin/plugin.json`.
TDD n/a (agent prose + version field); verification below.

- [ ] `pr-reviewer.md` opening paragraph: replace "You run on the strongest
  available model — the orchestrator must never spawn you with a cheaper
  `model:` override." with "Your model is chosen by the routing skill
  (`plugin/skills/routing/SKILL.md`) — never below the review floor, and
  never the same model family as the PR's sole author (independence rule,
  both directions)."
- [ ] Same file, Process step 1, add one sentence: "An advisory findings
  file from a cross-family reviewer may accompany the spawn — verify each
  finding yourself (confirm or dismiss); only findings YOU confirm get
  posted, under your name."
- [ ] `plugin/.claude-plugin/plugin.json`: version `0.1.18`.
- [ ] Verify: `jq -r .version` → 0.1.18; diff shows only the listed edits;
  `bats tests/` green.
- [ ] Commit: `pr-reviewer: routing-chosen model + advisory verify; bump 0.1.18`

## Self-review (done while planning)

- Spec → tasks: --sandbox flag ✓1, live verification ✓2, routing call before
  spawns + naming + codex lane + fallback + unverified-diff rule ✓3,
  advisory review + independence prose ✓4, version ✓4.
- `--workdir` is additive (not named in the spec's locked list but required
  by its "workdir = issue worktree" design line — runner cwd is undefined
  across visibility modes without it).
- Names consistent: `codex-gpt-5.6-sol--55-1` shape everywhere; sandbox
  values `read-only|workspace-write` everywhere.
- Out of scope guarded: no gate-mode codex review, no auto-run codex, no
  concurrent codex writers.

## Board

Single PR for issue #55 (exists, Ready for dev P1 after #54). Straight to
conveyor:executing-tasks.
