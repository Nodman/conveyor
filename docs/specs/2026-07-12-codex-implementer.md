# Codex as implementer + advisory reviewer (routing consumption)

Companion to `2026-07-12-model-routing.md` (same council verdict). Depends on
the routing skill existing.

## What

conveyor's executing-tasks consumes the routing skill: clear-spec plan tasks
go to codex gpt-5.6-sol in write mode inside the issue worktree; codex also
gives advisory cross-family PR reviews. `codex-exec.sh` grows a `--sandbox`
flag. Executor naming switches to the routing scheme.

## Why

- 5.6-sol codes at fable level (DeepSWE v1.1) on a flat-rate quota that is
  otherwise unused — routing it clear-spec implementation preserves claude
  quota for judgment work.
- Cross-family review catches what same-family review misses; council smoke
  runs already proved the read-only lane.

## Decisions (locked)

- **Routing call before every implementer spawn** — executing-tasks loads the
  routing skill and records the route in the spawn prompt.
- **Codex write lane**: `--sandbox read-only|workspace-write` on
  `codex-exec.sh run` (default read-only). Resume passes
  `-c 'sandbox_mode="workspace-write"'` — `resume` rejects `-s`
  (docs/gotchas/codex.md).
- **Codex implementers work only in the issue worktree**: edit files + run
  LOCAL tests. AMENDED 2026-07-12 after live verification (docs/gotchas/
  codex.md): the sandbox protects `.git` and blocks network — codex CANNOT
  commit or push. The orchestrator reviews the diff, commits under its own
  identity, and keeps push, PR, labels, board — unchanged gates.
- **Codex reviews are ADVISORY in v1**: read-only, findings to a file; the
  claude pr-reviewer gate verifies findings and does ALL posting (labels,
  comments, board). Codex becomes a gate only after benchmarked
  equal-or-better miss rates.
- **Review independence, both directions**: claude-authored code-heavy PRs
  get a codex advisory pass; codex-authored PRs get the claude gate; no
  model family reviews its own code as the only reviewer.
- **Naming**: `<runner>-<model>--<issue>-<n>` replaces `exec-<issue>-<n>`.
  Claude Agent names hyphenate model ids (no dots in charset); dotted ids
  only in codex labels/report paths.
- **Live-verify each new codex arg shape once** before relying on it
  (docs/gotchas/codex.md — arg-agnostic mocks hide CLI contracts).

## Design

### codex-exec.sh

- `run` gains `--sandbox read-only|workspace-write`; omitted → read-only.
  Fresh run: `-s <mode>`. Resume: `-c 'sandbox_mode="<mode>"'`.
- Everything else unchanged: report + log + sentinel-carries-exit-code,
  session-id capture, visibility ladder.
- Bats: arg building for both sandbox modes, fresh + resume, default
  read-only. Decisive assertion last (docs/gotchas/bats.md).

### executing-tasks changes

- Per plan task step 1 becomes: load routing skill → route → spawn.
  - Route = claude → Agent tool as today, `model:` explicit, name
    `claude-<model-id>--<issue>-<n>`.
  - Route = codex → `codex-exec.sh run --sandbox workspace-write` with
    workdir = issue worktree; prompt file carries the task text verbatim,
    output bar, report contract, comment-prefix rule, style rule.
    Wait on sentinel (timeout + background poll). Codex edits files and runs
    local tests in the worktree; it cannot commit, push, or open PRs
    (sandbox, see gotcha). The orchestrator judges the diff, reruns tests
    when needed, and commits under its own identity.
- Report judging, ledger, two-failures-take-over: unchanged. For codex the
  "resume by name" fix loop becomes resume by session id (from the run log).
- Parallel codex writers: only one write-mode codex per worktree at a time.
- Codex throttled/missing at spawn time → routing fallback (Opus), note in
  ledger. Codex sandbox blocks network/`gh`? Tests may not run inside the
  sandbox → executor reports "unverified diff"; orchestrator (or a claude
  executor) runs the tests before shipping — the gate assumes unverified
  diffs until test evidence exists.

### Review flow changes

- After PR opens: routing decides the advisory pass. Claude-authored
  code-heavy diff → codex advisory review: `codex-exec.sh run --sandbox
  read-only`, findings file; orchestrator hands the file to the claude
  pr-reviewer, which verifies each finding (dismiss/confirm) and posts as
  today. Codex-authored PR → claude gate alone (as today).
- `pr-reviewer.md` prose "strongest available model / never a cheaper
  override" → "model chosen by the routing skill; never below the review
  floor; never the same family as the PR's sole author".
- QA rotation: unchanged.

### Error handling

- Sentinel timeout → retry/resume once (routing ladder), then Opus fallback.
- Codex cannot commit (verified — protected `.git`): the orchestrator
  commits the diff; commits carry the orchestrator's git identity.
- Worktree conflict (codex writing where a claude executor works) → routing
  rule: one implementer per worktree, sequential.

### Testing

- Bats: codex-exec.sh sandbox arg shapes (fresh + resume + default).
- Live verification checklist (plan task, once): workspace-write edit,
  resume-with-write, git commit inside worktree, test run inside sandbox,
  network/`gh` availability. Results recorded in docs/gotchas/codex.md.
- End-to-end QA per running-the-app: one real plan task routed to codex,
  full lifecycle to merge-ready.

### Version

- Touches `plugin/` → patch bump in `plugin/.claude-plugin/plugin.json`.

## Out of scope (v1)

- Codex as review GATE (needs miss-rate benchmark).
- Codex in `/conveyor:auto` runs (prove the plain lane first).
- Multiple concurrent codex writers per issue.
- Quota telemetry / pre-throttle detection.
