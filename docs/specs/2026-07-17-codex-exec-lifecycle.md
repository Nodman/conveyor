# codex-exec lifecycle hardening (council verdict)

## What

Seven small changes to `plugin/scripts/codex-exec.sh`, two skill/doc folds, and
mock/test coverage — adopted from a council analysis of
[openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc) (OpenAI's
official Codex plugin for Claude Code).

## Why

- Council (claude-fable-5 + codex-gpt-5.6-sol, 2026-07-17) compared their
  runtime to ours. Verdict: their Node infrastructure is not worth copying;
  their lifecycle discipline is.
- Two live defects confirmed in our script:
  - resume drops the model — fresh passes `-m`, `codex exec resume` doesn't
    (`codex-exec.sh:201-203`). Escalating a resumed session silently no-ops.
  - sentinel records only codex's exit code (`codex-exec.sh:221`); exit 0 with
    a missing/empty report is a recorded failure class (`docs/gotchas/codex.md`).
- A full-access background codex has no stop handle: pid discarded at spawn
  (`codex-exec.sh:256`).

## Decisions (locked)

- Stay bash + jq + markdown. No Node runtime, no daemon, no broker, no shared
  state registry (simplicity/yolo rulings, `docs/DECISIONS.md`).
- Resume stays explicit-session-id only. No resume-last, no thread search.
- Login preflight stays fail-fast. No optimistic execution.
- Keep the generated `.run.sh`. Controller/worker + manifest rewrite deferred —
  no observed failure traces to it.
- `status` derives state from files that already exist (sentinel, log
  mtime/tail) plus ONE write-once spawn record. Nothing mutates job state.
- Prompt improvements fold into existing docs. No new template files.

## Design

1. **Resume model parity** — pass `-m $model` on `codex exec resume`
   (`codex-exec.sh:203`). Also apply `--effort` (item 5) on both paths when
   given; nothing is passed when the flag is absent.
2. **Report validation before success** — sentinel written last; code 0 only
   when codex exited 0 AND report exists non-empty AND parses as JSON when
   `--output-schema` was given. Otherwise nonzero sentinel + reason in log.
3. **Spawn record + `kill`** — runner writes `<out>.job` once at spawn:
   pid/pgid (background) or pane id (tmux), start time, name, model, workdir.
   `codex-exec.sh kill <report.md>`: TERM → grace → KILL the group / kill the
   pane. Dumb kill — no pid-reuse identity check (judge trim: guard
   machinery). Never writes the worker's sentinel.
4. **`status` + `wait`** — `status <report.md>`: done(code) | running | dead,
   derived from sentinel + `.job` + process/pane liveness. No phase parsing
   (judge trim). `wait <report.md> --timeout <s>`: bounded poll, re-callable,
   timeout ≤ Bash-tool cap. Council + executing-tasks skills replace their
   poll prose with these calls.
5. **`--effort` flag** — optional, maps to `-c model_reasoning_effort=<v>`,
   unset by default; validate enum; live-verify once (gotcha rule), record
   result in `docs/gotchas/codex.md`.
6. **Prompt folds** — exact clauses, condensed from openai/codex-plugin-cc
   `prompts/adversarial-review.md` and `skills/gpt-5-4-prompting/SKILL.md`:
   - Into `plugin/agents/pr-reviewer.md` (Process step 3):
     - attack surface: prioritize expensive/hard-to-detect failures — auth,
       permissions, trust boundaries; data loss, corruption, irreversible
       state; rollback, retries, partial failure, idempotency; races,
       ordering, stale state; empty/null/timeout/degraded-dependency paths;
       version skew, schema drift; observability gaps that hide failure.
     - finding bar: each finding answers what goes wrong, why this path is
       vulnerable, likely impact, concrete fix.
     - calibration: one strong finding beats several weak ones; never dilute
       serious issues with filler.
     - grounding: findings defensible from the diff/code only; a conclusion
       resting on inference says so explicitly.
   - Into `plugin/skills/routing/references/delegation-contract.md`:
     - one task per run; unrelated asks are separate runs.
     - resume sends only the delta instruction, never the restated prompt,
       unless direction changed materially.
     - claims anchored to observed evidence; hypotheses labeled as such.
     - weak result → tighten the prompt contract before raising model/effort.
7. **Mock + tests** — extend `tests/helpers/bin/codex` with slow-run,
   missing-report, and signal-death modes; bats coverage for new subcommands
   and both resume arg shapes.

Error handling: `kill`/`status` on unknown paths → clear die. Testing: bats
via mock first, one live smoke of fresh/resume/kill/wait after.

## Member positions (condensed)

- **codex-gpt-5.6-sol**: pushed controller/worker + `.job.json` manifest
  (deferred); found the resume-model drop; conceded the broker is useless for
  parallel councils; argued prompt clauses belong in existing docs (adopted).
- **claude-fable-5**: opened minimal-infra (pid file, derived status, effort
  flag); conceded report validation, `wait`, tracked cancel; killed preflight
  relaxation and any second writer for phase/heartbeat.
- Verdict merged by the main session. Raw round-1/round-2 reports stayed in
  session scratch (not committed).
- **spec-judge-98** (fable, human-requested pre-plan review): NEEDED-BUT-TRIM.
  Applied: dumb kill (no identity check), no phase parsing in `status`,
  `--effort` default = pass nothing, item 6 clauses inlined verbatim.

## Out of scope

- Controller/worker + per-run manifest rewrite (revisit if run shapes grow).
- Structured review-findings schema (revisit if finding-routing pain appears).
- Everything rejected: app-server/broker, `state.json` registry, resume-last,
  transcript transfer, stop-review-gate hook, session-end kill, sandbox
  machinery, native `review/start`, rescue-forwarder agent.
