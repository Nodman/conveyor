---
name: routing
description: Use before spawning ANY subagent or external agent — picks the model for a delegated task (class → quality floor → runner fit → cheapest floor-passer) and the escalation path. Load whenever choosing a model or writing a spawn prompt.
---

# Model routing

Policy only. The pool table, scores, and runner friction live in
`references/model-pool.md`. Spawn-prompt fields, naming, repair, and the
external-runner contract live in `references/delegation-contract.md`.

## Availability gate

Codex rows apply only when the codex CLI is installed + authed (in conveyor
repos: `codex-exec.sh preflight`). Check once per session. Failing → use the
claude-only pool, silently — no codex mentions to the user.

## Per-repo override

Optional `.claude/routing.md`, same table format as `references/model-pool.md`.
Its rows replace/extend the defaults. Malformed → ignore it, use the defaults,
tell the user.

## Defaults, not limits

- Standing permission to escalate: a cheaper model's output misses the bar →
  rerun or redo with a smarter model, without asking. Judge the output, not
  the price tag — escalating costs less than shipping mediocre work.
- Cost never blocks the right model for the job. Use cheap models to gather
  information and try things first, then move the work up when it matters.
- Anything user-facing (UI, copy, API design) needs taste ≥ 7.

## Decision procedure (run top-down)

1. Write the output bar BEFORE choosing: acceptance criteria, required
   evidence, risk, taste requirement. It goes in the spawn prompt; escalation
   judges against it.
2. Don't delegate one grep/read/already-loaded small step.
3. Classify: judgment / taste / code / legwork / review.
4. Quality floors: judgment → strongest model, main session, never delegated
   (main session below the floor → delegate judgment UP, don't assume the
   director is strongest). Taste ≥7 — Fable decides, Opus executes settled
   design. Complex code → highest-intel implementer: 5.6-sol or Opus (Opus
   when harness integration or repo-law judgment). Routine clear-spec
   code → 5.6-sol or 5.5. Exploration,
   throwaway prototypes, bulk mechanical code → 5.5 (taste 5 — never
   user-facing output). Legwork → sonnet-5.
   High-risk review (security/concurrency/data-loss/auth/migration) →
   Fable + cross-family second opinion.
5. Runner constraints: live steering / tool permissions / in-band report /
   teammate resume → Agent tool. Codex is a full lane (edits, tests, commits,
   pushes, gates) — no sandbox constraint; but no mid-run steering, so prefer
   well-scoped tasks. Codex throttled/missing → fall back to Opus.
6. Among floor-passers, pick lowest expected TOTAL burn: output + likely
   repair runs + orchestration overhead, across whichever quota pool it
   drains — not nominal per-token price.
7. Record the route in the spawn prompt (class, floor, model, reason,
   escalation target). Never ask the human.

## Escalation ladder (automatic, logged in spawn prompts/ledger)

- Infra failure → retry/resume same model once.
- Small localized defect → ONE targeted repair via resume (SendMessage /
  `codex exec resume <sid>`), never respawn. One repair max.
- Wrong approach / weak reasoning / second substantive miss → escalate:
  sonnet → opus (taste/repo-law) or 5.6-sol (intel); 5.5 → 5.6-sol or opus;
  opus/5.6-sol → Fable takes it itself; second substantive miss anywhere →
  Fable directly. Pass original task + failed output + exact defects to the
  replacement.
- Reviewer disagreement on a blocking issue → Fable adjudicates.
- Required reviews are never dropped for quota pressure — substitute another
  qualifying reviewer.

## Review independence

Never self-review by model family, both directions. High-risk review →
strongest model + cross-family second opinion.
