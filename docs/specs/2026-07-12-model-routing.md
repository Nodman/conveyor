# Model routing — skill + references (in conveyor)

Council-designed (members: claude-fable-5, codex-gpt-5.6-sol; two rounds).
Verdict + user amendments: `.conveyor/council-routing/verdict.md`.

## What

`plugin/skills/routing/` — a policy skill that decides WHICH model executes
WHICH delegated task, loaded by any orchestrator before spawning subagents.
Pure policy in human-editable markdown: no scripts, no interactive config.
Replaces the "Model routing" section of the user's global `~/.claude/CLAUDE.md`.

## Why

- Routing rules today live in one user's global CLAUDE.md — not versioned,
  not portable, silent drift.
- codex (gpt-5.6-sol) proved council-grade; benchmarks (DeepSWE v1.1) put its
  code quality at claude-fable-5 level. A rules file is needed to use it —
  and cheaper claude tiers — without sacrificing quality.

## Decisions (locked)

- **Lives INSIDE conveyor** (user ruling, reverses earlier two-plugin plan):
  a routing-only plugin has no runner — policy without execution is useless
  standalone. Extract a policy-only plugin later if a second consumer appears.
- **Human-editable markdown everywhere** (user ruling): rules and pool are
  plain `.md` a human can edit directly. No JSON knobs, no setup wizard.
- **No dollar/plan modeling** (user ruling): both providers are flat-rate
  subscriptions; tiers vary per user and don't change routing. No price
  tables, no billing questions. Rank by capability; quotas are pools that
  drain ("if it drains, it drains") with fallback on throttle.
- **Pool**: claude fable-5 / opus-4.8 / sonnet-5 (Agent tool) +
  codex gpt-5.6-sol (external runner). gpt-5.5 excluded (weaker at the same
  everything, worst credit burn). haiku banned (user rule). Pool changes
  require a measured end-to-end win on a repo task suite — same pass+repair
  bar.
- **Scores are user-prior + benchmark-informed**, marked contested where
  members disagreed; re-calibrate when repo benchmarks exist.
- **Codex availability gate**: codex pool rows apply only when the codex CLI
  is installed + authed; otherwise routing silently runs claude-only.
- **Quality floor before cost, always.** Judgment is never delegated.
- **Review independence**: never self-review by model family, both directions.

## Design

### Files

- `plugin/skills/routing/SKILL.md` — decision procedure + escalation ladder.
  Description triggers on: spawning any subagent, choosing a model for
  delegated work.
- `plugin/skills/routing/references/model-pool.md` — pool table + friction
  notes. Every row carries `asOf` date + source + confidence.
- `plugin/skills/routing/references/delegation-contract.md` — spawn-prompt
  fields, output-bar rubric, naming, repair rules, and the external-runner
  CONTRACT (command shapes incl. `-s` fresh / `-c 'sandbox_mode=...'` resume,
  report + log + sentinel-carries-exit-code, session-id capture, timeout +
  background poll) so any repo/orchestrator can implement a compatible
  runner (~30 lines).
- Per-repo override: optional `.claude/routing.md` — same table format as
  model-pool.md; rows there replace/extend the defaults. Markdown, hand-edited.

### model-pool.md initial content

Scores 1-10, higher better. Sources: user ruling 2026-07-12; DeepSWE v1.1
leaderboard 2026-07-09 (113 tasks); practitioner table (video, lacks 5.6).

| model | runner | intel | taste | code | control | notes |
|---|---|---|---|---|---|---|
| claude-fable-5 | Agent tool | 9 | 9 | 9 | native 10 | director; judgment floor |
| claude-opus-4-8 | Agent tool | 8 | 8 | 8 | native 10 | harness/repo-law implementer |
| claude-sonnet-5 | Agent tool | 6 | 7 | 7 | native 10 | legwork |
| codex-gpt-5.6-sol | codex CLI | 8 | 8 | 9 | external 5 | DeepSWE ≈ fable at code; quota-gated |

- Benchmark note: DeepSWE v1.1 — 5.6-sol peaks ~73% vs fable-5 ~70%,
  opus-4.8 ~52-60%, sonnet-5 ~48-54%. Scores re-calibrate when a shared repo
  task suite exists.
- Friction/control: Agent tool = permissions, in-band result, SendMessage
  resume, visible in token budgets. codex CLI = file report + log + sentinel,
  session-id resume only, no mid-run steering, INVISIBLE to harness token
  budgets (track separately), parallel writes need worktree isolation.
- Availability: codex rows require `codex` installed + authed (in conveyor:
  `codex-exec.sh preflight`); failing → claude-only pool, no codex mentions.

### SKILL.md decision procedure (run top-down)

1. Write the output bar BEFORE choosing: acceptance criteria, required
   evidence, risk, taste requirement. It goes in the spawn prompt;
   escalation judges against it.
2. Don't delegate one grep/read/already-loaded small step.
3. Classify: judgment / taste / code / legwork / review.
4. Quality floors: judgment → strongest model, main session, never delegated
   (main session below the floor → delegate judgment UP, don't assume the
   director is strongest). Taste ≥7 — Fable decides, Opus executes settled
   design. Complex code → 5.6-sol or Opus (Opus when harness integration or
   repo-law judgment). Routine clear-spec code → 5.6-sol. Legwork → sonnet-5.
   High-risk review (security/concurrency/data-loss/auth/migration) →
   Fable + cross-family second opinion.
5. Runner constraints: live steering / tool permissions / in-band report /
   teammate resume → Agent tool. Isolated well-specified implementation or
   read-only review → codex; write jobs in dedicated worktrees; codex
   throttled/missing → fall back to Opus.
6. Among floor-passers, pick lowest expected TOTAL burn: output + likely
   repair runs + orchestration overhead, across whichever quota pool it
   drains — not nominal per-token price.
7. Record the route in the spawn prompt (class, floor, model, reason,
   escalation target). Never ask the human.

### Escalation ladder (automatic, logged in spawn prompts/ledger)

- Infra failure → retry/resume same model once.
- Small localized defect → ONE targeted repair via resume (SendMessage /
  `codex exec resume <sid>`), never respawn. One repair max.
- Wrong approach / weak reasoning / second substantive miss → escalate:
  sonnet → opus or 5.6-sol (taste vs code); opus/5.6-sol → Fable takes it
  itself; second substantive miss anywhere → Fable directly. Pass original
  task + failed output + exact defects to the replacement.
- Reviewer disagreement on a blocking issue → Fable adjudicates.
- Required reviews are never dropped for quota pressure — substitute another
  qualifying reviewer.

### delegation-contract.md content

- Spawn-prompt fields: goal, output bar, evidence required, report format
  (condensed bullets, file:line refs), escalation target, comment-prefix
  rule, communication style (short sentences, lead with the answer).
- Naming: canonical `<runner>-<model>`, uniqueness suffix `--<issue>-<n>`.
  Agent tool charset `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` — no dots → claude
  names hyphenate ids (`claude-opus-4-8--48-2`); dotted ids only in codex
  labels/report paths (`codex-gpt-5.6-sol--48-1`). ALWAYS set `model:`
  explicitly in Agent calls — omission silently inherits the main model.
- Repair rules (the ladder above, from the spawner's side).
- External-runner contract (see Files above) — documents conveyor's
  `codex-exec.sh` behavior as the reference implementation.

### Error handling

- codex missing/unauthed → preflight catches it; routing degrades to
  claude-only silently (doctor mentions it once, see below).
- codex quota throttled mid-run → fallback rule (Opus) + note in ledger.
- Override file malformed → ignore it, use defaults, tell the user.

### init/doctor touch

- `init`: if codex absent, say codex lanes are dormant until installed
  (one line, no question).
- `doctor`: flags codex-configured-but-missing (or newly installed →
  routing can use it).

### Testing

- Policy is markdown — no bats surface of its own. Live QA per
  `running-the-app`: one routed spawn per class, verify route recorded in
  spawn prompt + name format.
- Runner/consumption changes are covered by the codex-implementer spec.

### Rollout

- User's global `~/.claude/CLAUDE.md` "Model routing" section is REPLACED by
  this skill after it ships (user edits, or asks us). Until then the global
  section governs live sessions.

## Out of scope (v1)

- Separate/extracted routing plugin (revisit on a second real consumer).
- Benchmark harness for score calibration (gate for future pool changes).
- gpt-5.5 (summonable ad hoc via the model-agnostic runner in outages).
- Dollar-cost accounting, plan tiers, quota telemetry.
- executing-tasks/pr-reviewer consumption — companion spec
  `2026-07-12-codex-implementer.md`.
