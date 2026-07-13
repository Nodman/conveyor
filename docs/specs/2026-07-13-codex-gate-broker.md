# Codex full gate + typed action broker — spec

Council-approved design (2026-07-13). Members: claude-fable-5, codex-gpt-5.6-sol.
Two proposal rounds + rebuttal; verdict merged by the session lead. Raw artifacts in session scratch.

## What

Promote codex-gpt-5.6-sol from advisory reviewer to full PR review gate and
committing executor, without ever giving it credentials or network. A new typed
action broker (`codex-actions.sh`) executes codex's schema-bound decisions under
the orchestrator's gh identity. Reviewer priority becomes 5.6-sol → Fable → Opus.

## Why

- Advisory proxying double-burns every codex review (codex reviews, claude
  re-verifies and posts).
- 5.6-sol is the strongest code model in the pool (DeepSWE ~73% vs fable ~70%,
  opus ~52-60%) but was capped at read-only advice.
- Direct credentials (PAT) rejected: a prompt-injected model with a token and
  egress can exceed any API scope; a secret must never enter model-controlled
  execution.

## Decisions (locked)

- **No token, no network, ever.** Codex stays in `read-only|workspace-write`;
  `danger-full-access` stays rejected by codex-exec.sh. All GitHub/git writes go
  through the broker under the orchestrator's existing gh auth.
- **Codex is a FULL gate.** Its verdict posts as the review round — no second
  model re-verifies its reasoning. The broker validates actions, not reasoning.
  Advisory-proxy flow is deleted.
- **Structured output.** Codex gate/executor runs use `codex exec
  --output-schema` (live-verified 0.144.1, fresh AND resume) emitting
  `review-verdict.json` / `commit-request.json` shapes.
- **Broker is minimal and separate.** `codex-actions.sh`, three subcommands:
  - `bundle <pr>` — immutable local review bundle: PR/issue metadata, diff,
    threads, expected head SHA, trusted label config (read from base checkout,
    never the PR branch).
  - `review <pr> <verdict.json>` — head-SHA staleness check; posts ONE inline
    review in the pr-reviewer.md shape; thread replies on re-rounds; labels
    restricted to conveyor.json `labels` values; injects the `**[<agent-name>]**`
    prefix from trusted args (model can't spoof/omit identity).
  - `commit <worktree> <manifest.json>` — clean-tree check, stage exactly the
    manifest paths, author = `<agent-name> <codex@conveyor.invalid>`, committer =
    orchestrator, `Conveyor-Model:` + `Conveyor-Session:` trailers.
  - No local diff-anchor validation — GitHub's API 422 is the authority; surface
    it for one repair round. Keeps a slim action record (executed actions,
    GitHub IDs, exit codes) in `.conveyor/` so partial failures reconcile by
    stored IDs, never blind repost. No input/output hashing.
- **Sentinel semantics unchanged.** Sentinel carries the codex exit code only;
  broker has its own exit status. Codex fail → session-id resume (one repair);
  broker fail → rerun broker. codex-exec.sh stays a generic runner — gains only
  `--output-schema` passthrough.
- **Commits are orchestrator-judged.** Broker prepares; orchestrator judges the
  diff (reruns tests codex couldn't) before invoking `commit`. Review posting
  needs no such gate (parity with claude reviewers).
- **Reviewer ladder: 5.6-sol → Fable → Opus**, skipping every model that
  materially authored the PR. `family` = model lineage (gpt-5.6, fable-5,
  opus-4, sonnet-5).
- **Executor routing:** routine + complex code → 5.6-sol; harness/live-steering
  fit → Opus; **all high-risk work → Opus** (a 5.6 high-risk author would make
  the mandatory cross-provider opinion a self-review); judgment/taste → Fable
  directs, another model implements.
- **High-risk floor unchanged:** Fable gate + cross-provider second opinion;
  codex missing there → retry once, then safe-stop in Agent Review. Never
  weakened for quota pressure.
- **Escalation split:** throttle/infra → Opus; substantive quality miss → Fable;
  reviewer disagreement → Fable adjudicates.
- **Orchestrator keeps** card moves, push, `ready-to-merge`, merge.
- **Ratified trade-off:** with 5.6 authoring most code, Fable gates most PRs by
  volume; "5.6 top reviewer" holds per-eligibility (whenever 5.6 isn't the
  author). Strongest author + second-strongest gate over the reverse.
- **PR attribution:** visible `Conveyor-Agent:` line in the PR body (lands in
  squash history); no hidden metadata.
- **conveyor.json unchanged** (no routing knobs, no credentials — routing stays
  markdown); pluginVersion bump only.

## Design

Artifact changes (product source `plugin/`):

- `scripts/codex-exec.sh` — add `--output-schema <file>` passthrough (fresh +
  resume); sandbox allowlist and sentinel untouched.
- NEW `scripts/codex-actions.sh` — bundle/review/commit as above; preflight for
  jq/git/gh auth/schema files.
- NEW `schemas/review-verdict.json`, `schemas/commit-request.json`.
- `agents/pr-reviewer.md` — transport-neutral charter: claude transport (direct
  gh, unchanged) + codex transport (read bundle, emit verdict object; broker
  posts under your name; report broker action ids). Verdict semantics, severity
  order, same-account `event=COMMENT` rule unchanged.
- `skills/routing/SKILL.md` — rotation matrix + reviewer ladder; drop "codex =
  isolated impl or read-only review only"; split throttle vs quality
  escalation; independence section: family keys, material-author exclusion,
  high-risk-5.6-implementation prohibition.
- `skills/routing/references/model-pool.md` — family column; codex notes =
  "preferred code executor + gate for claude-authored PRs; brokered actions, no
  live steering"; opus = "high-risk/harness executor; throttle fallback";
  friction notes gain bundle/schema/broker steps.
- `skills/executing-tasks/SKILL.md` — codex lane: broker commit after
  orchestrator judgment (replaces orchestrator-identity commits); Ship: gate per
  ladder, advisory flow deleted, codex gate spawned with pr-reviewer.md body +
  bundle + `--output-schema`; fix loop (resume by sid) unchanged; PR body gains
  `Conveyor-Agent:` line.
- `skills/council/SKILL.md` — run lines gain `--workdir <repo>` (r1 crashed
  without it: codex refuses untrusted cwd).
- Tests: stale head SHA, forbidden label, path-outside-manifest, dirty
  worktree, prefix injection, sentinel unchanged on broker failure,
  `--output-schema` fresh+resume (mocks must reject what the real CLI rejects).
- `docs/DECISIONS.md` — record the no-token-broker ruling and the ratified
  reviewer-volume trade-off.
- `docs/gotchas/codex.md` — record `--output-schema` live results after first
  real run.

## Out of scope

- Direct codex commits (`.git` unprotect) — revisit when codex issue #14338
  lands.
- Bot/machine GitHub account for codex identity.
- Card moves, push, merge from the broker.
- gpt-5.5 pool re-entry; any Haiku use.
- Per-repo routing overrides beyond the existing `.claude/routing.md` hook.

## Member positions (trace)

- codex-gpt-5.6-sol won: no-token broker mechanism, structured output over
  prose parsing, commit authorship form (codex author / orchestrator
  committer), material-author exclusion, high-risk-executor-must-be-Opus rule,
  action-ID reconciliation.
- claude-fable-5 won: minimal broker (no diff re-validation, no hash audit),
  codex-only sentinel + separate broker script, generic-runner contract,
  orchestrator judgment before commits, `bundle` subcommand, visible
  attribution over hidden metadata, decision-record duty.
- Lead rulings: slim action record kept (reconciliation is load-bearing);
  broker stays out of codex-exec.sh; user ratified the reviewer-volume
  trade-off.
