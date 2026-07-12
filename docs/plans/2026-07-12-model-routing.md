# Plan: model routing skill

Spec: `docs/specs/2026-07-12-model-routing.md` (read it first — Decisions are
locked there). Council verdict: `.conveyor/council-routing/verdict.md`.

**Goal:** ship `plugin/skills/routing/` — a pure-markdown policy skill that
picks the model for every delegated spawn.

**Architecture:** one skill + two reference files, all human-editable
markdown. No scripts, no JSON config. Orchestrators load the skill before
spawning; codex rows apply only when the codex CLI passes preflight. Per-repo
override is an optional `.claude/routing.md` in the same table format.

**Global constraints (from spec, locked):**
- Human-editable markdown only — no scripts, no JSON knobs, no setup wizard.
- No dollar prices, plan tiers, or billing anywhere in the content.
- Scores: fable-5 9/9/9 · opus-4-8 8/8/8 · sonnet-5 6/7/7 ·
  gpt-5.6-sol intel 8 / taste 8 / code 9 (order: intel/taste/code).
- Naming: `<runner>-<model>--<issue>-<n>`; Agent-name charset
  `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` (no dots).
- gpt-5.5 excluded; haiku banned; judgment never delegated.
- PR touches `plugin/` → version bump 0.1.16 → 0.1.17.
- Style: short sentences, condensed bullets, no filler (this repo's law).

## File map

| File | Responsibility |
|---|---|
| `plugin/skills/routing/references/model-pool.md` (new) | pool table + scores + benchmark note + friction/control + availability rule |
| `plugin/skills/routing/references/delegation-contract.md` (new) | spawn-prompt fields, output-bar rubric, naming, repair rules, external-runner contract |
| `plugin/skills/routing/SKILL.md` (new) | decision procedure + escalation ladder + override + degradation |
| `plugin/skills/init/SKILL.md` (modify) | one line: codex absent → routing codex lanes dormant |
| `plugin/skills/doctor/SKILL.md` (modify) | one session check: codex availability vs routing |
| `plugin/.claude-plugin/plugin.json` (modify) | version 0.1.17 |

## Task 1 — reference files

Files: `plugin/skills/routing/references/model-pool.md`,
`plugin/skills/routing/references/delegation-contract.md`.
Interfaces produced: the two reference paths, cited by SKILL.md in task 2.

TDD n/a — markdown content; verification is a checklist against the spec.

- [ ] Write `model-pool.md` with exactly these sections:
  - Header: scores 1-10, higher better; sources line:
    `user ruling 2026-07-12 · DeepSWE v1.1 leaderboard 2026-07-09 (113 tasks) · practitioner table (video, lacks 5.6)`.
  - Pool table (verbatim):

    | model | runner | intel | taste | code | control | notes |
    |---|---|---|---|---|---|---|
    | claude-fable-5 | Agent tool | 9 | 9 | 9 | native 10 | director; judgment floor |
    | claude-opus-4-8 | Agent tool | 8 | 8 | 8 | native 10 | harness/repo-law implementer |
    | claude-sonnet-5 | Agent tool | 6 | 7 | 7 | native 10 | legwork |
    | codex-gpt-5.6-sol | codex CLI | 8 | 8 | 9 | external 5 | DeepSWE ≈ fable at code; quota-gated |

  - Benchmark note: DeepSWE v1.1 — 5.6-sol peaks ~73% vs fable-5 ~70%,
    opus-4-8 ~52-60%, sonnet-5 ~48-54%; re-calibrate when a shared repo task
    suite exists.
  - Excluded rows: gpt-5.5 (same price class, weaker, worst credit burn;
    re-entry = measured ≥30% cheaper end-to-end at same pass+repair rate);
    haiku (user-banned).
  - Friction/control: Agent tool = permissions, in-band result, SendMessage
    resume, visible in token budgets. codex CLI = file report + log +
    sentinel-carries-exit-code, session-id resume only, no mid-run steering,
    INVISIBLE to harness token budgets (track separately), parallel writes
    need worktree isolation.
  - Availability: codex rows require the codex CLI installed + authed
    (conveyor: `codex-exec.sh preflight`); failing → claude-only pool, don't
    mention codex options to the user.
  - Quota framing: both providers flat-rate subscriptions; quotas are pools
    that drain; throttle → fallback per SKILL.md ladder. NO dollar figures.
- [ ] Write `delegation-contract.md` with exactly these sections:
  - Spawn-prompt fields (every delegated spawn): goal; output bar
    (acceptance criteria, required evidence, risk, taste requirement);
    report format (condensed bullets, `file:line` refs, no full file dumps,
    "nothing found" said plainly); escalation target; comment-prefix rule
    (`**[<agent-name>]**`); communication style (short sentences, lead with
    the answer); the route record (class, floor, model, reason).
  - Output-bar rubric: bar is written BEFORE model choice; escalation judges
    the deliverable against the bar, not against taste-of-the-day.
  - Naming: canonical `<runner>-<model>`, uniqueness suffix `--<issue>-<n>`;
    Agent tool charset `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` — no dots → claude
    names hyphenate model ids (`claude-opus-4-8--48-2`); dotted ids only in
    codex labels/report paths (`codex-gpt-5.6-sol--48-1`); ALWAYS set
    `model:` explicitly in Agent calls — omission silently inherits the main
    model.
  - Repair rules (spawner side): infra failure → retry/resume same model
    once; small localized defect → ONE targeted repair via resume
    (SendMessage / `codex exec resume <sid>`), never respawn, one repair max;
    then escalate per SKILL.md ladder.
  - External-runner contract (reference implementation: conveyor's
    `plugin/scripts/codex-exec.sh`) — a compatible runner MUST provide:
    - fresh run: sandbox via `-s <mode>`; resume: `codex exec resume <sid>`
      REJECTS `-s`, pass `-c 'sandbox_mode="<mode>"'` instead;
    - report file (the deliverable) + log file + sentinel file whose content
      carries the exit code, touched after exit in every visibility mode;
    - session-id capture from the run header (for resume; never `--last`);
    - explicit timeout + background poll on the sentinel;
    - model-agnostic `-m <model>` (excluded models stay summonable ad hoc,
      e.g. outages). ~30 lines of shell for a minimal runner.
- [ ] Verify: `grep -c '\$' model-pool.md` → 0 dollar signs; both files
  contain every section above; no "TBD"/placeholder text.
- [ ] `bats tests/` green (no scripts touched — gate stays green).
- [ ] Commit: `routing: model pool + delegation contract references`

## Task 2 — routing SKILL.md

Files: `plugin/skills/routing/SKILL.md`.
Interfaces consumed: the two reference paths from task 1 (cite as
`references/model-pool.md`, `references/delegation-contract.md`).

TDD n/a — markdown; verification checklist.

- [ ] Frontmatter:

  ```yaml
  ---
  name: routing
  description: Use before spawning ANY subagent or external agent — picks the model for a delegated task (class → quality floor → runner fit → cheapest floor-passer) and the escalation path. Load whenever choosing a model or writing a spawn prompt.
  ---
  ```

- [ ] Body sections, in order:
  - Intro (2 lines): policy only; pool + friction in
    `references/model-pool.md`, spawn-prompt/naming/runner rules in
    `references/delegation-contract.md`.
  - Availability gate: codex rows apply only when the codex CLI is installed
    + authed (in conveyor repos: `codex-exec.sh preflight`); check once per
    session; failing → claude-only pool, silent (no codex mentions to user).
  - Per-repo override: `.claude/routing.md`, same table format as
    model-pool.md; its rows replace/extend defaults; malformed → ignore,
    use defaults, tell the user.
  - Decision procedure — transcribe the spec's 7 steps verbatim
    (spec "SKILL.md decision procedure" section): output bar first;
    don't delegate one grep/read; classify judgment/taste/code/legwork/
    review; quality floors (incl. delegate-judgment-UP rule); runner
    constraints; lowest expected TOTAL burn among floor-passers; record the
    route in the spawn prompt, never ask the human.
  - Escalation ladder — transcribe the spec's ladder verbatim (automatic,
    logged in spawn prompts/ledger; required reviews never dropped for quota
    pressure — substitute another qualifying reviewer).
  - Review independence: never self-review by model family, both directions;
    high-risk review → strongest model + cross-family second opinion.
- [ ] Verify: every spec "Design" bullet for SKILL.md maps to a section;
  no prices; no JSON; description triggers on "spawning any subagent".
- [ ] Verify skill loads: `claude plugin` cache not required — structural
  check only: frontmatter parses (name + description present, `---` fences).
- [ ] Commit: `routing: decision-procedure skill`

## Task 3 — init/doctor touch + version bump

Files: `plugin/skills/init/SKILL.md`, `plugin/skills/doctor/SKILL.md`,
`plugin/.claude-plugin/plugin.json`.

TDD n/a — markdown + version field; verification checklist.

- [ ] `init/SKILL.md` step 4 (external-agent visibility paragraph): append
  one sentence: "codex CLI absent → say once that routing's codex lanes stay
  dormant until it is installed (no question)."
- [ ] `doctor/SKILL.md` step 2 (session-level checks): add one bullet:
  "`codex-exec.sh preflight` fails while `plugin/skills/routing/` ships codex
  pool rows → note codex lanes dormant (install + auth codex to enable);
  preflight passes but earlier doctor runs flagged dormancy → note codex
  lanes now active."
- [ ] `plugin/.claude-plugin/plugin.json`: `"version": "0.1.17"`.
- [ ] Verify: `jq -r .version plugin/.claude-plugin/plugin.json` → `0.1.17`;
  both skill edits are single-bullet/sentence surgical additions (diff shows
  nothing else).
- [ ] `bats tests/` green.
- [ ] Commit: `routing: init/doctor codex-availability notes; bump 0.1.17`

## Self-review (done while planning)

- Spec → tasks: references ✓1, SKILL ✓2, override rule ✓2, availability
  gate ✓1+2+3, init/doctor ✓3, version ✓3, error handling (malformed
  override, silent degradation) ✓2, no-prices ✓1+2 verify steps.
- Rollout (not a repo task): after merge + plugin update, user's global
  `~/.claude/CLAUDE.md` "Model routing" section gets replaced — remind the
  human in the merge-ready report.
- Live QA (spec Testing): one routed spawn per class via running-the-app —
  belongs to the executing-tasks QA step, noted for qa-agent.

## Board

Single PR. One agent-task issue for the card (executing-tasks needs
`Fixes #n`); spec B (`2026-07-12-codex-implementer.md`) queues as its own
Ready-for-dev issue, planned separately after this ships.
