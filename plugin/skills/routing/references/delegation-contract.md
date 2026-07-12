# Delegation contract

## Spawn-prompt fields

Every delegated spawn states:

- **Goal** — the exact task.
- **Output bar** — acceptance criteria, required evidence, risk, taste
  requirement.
- **Report format** — condensed bullets, `file:line` refs, no full file
  dumps; say "nothing found" plainly.
- **Escalation target** — who takes it on a miss.
- **Comment-prefix rule** — GitHub comments start with `**[<agent-name>]**`.
- **Communication style** — short sentences, lead with the answer.
- **Route record** — class, floor, model, reason.

## Output-bar rubric

Write the bar BEFORE choosing the model. Escalation judges the deliverable
against the bar, not against taste-of-the-day.

## Naming

- Canonical `<runner>-<model>`; uniqueness suffix `--<issue>-<n>`.
- Agent tool charset `^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$` — no dots. Claude
  names hyphenate model ids (`claude-opus-4-8--48-2`).
- Dotted ids only in codex labels/report paths
  (`codex-gpt-5.6-sol--48-1`).
- ALWAYS set `model:` explicitly in Agent calls — omission silently inherits
  the main model.

## Repair rules (spawner side)

- Infra failure → retry/resume same model once.
- Small localized defect → ONE targeted repair via resume (SendMessage /
  `codex exec resume <sid>`), never respawn. One repair max.
- Then escalate per SKILL.md ladder.

## External-runner contract

Reference implementation: conveyor's `plugin/scripts/codex-exec.sh`. A
compatible runner MUST provide:

- Fresh run: sandbox via `-s <mode>`. Resume: `codex exec resume <sid>`
  REJECTS `-s` — pass `-c 'sandbox_mode="<mode>"'` instead.
- Report file (the deliverable) + log file + sentinel file whose content
  carries the exit code, touched after exit in every visibility mode.
- Session-id capture from the run header (for resume; never `--last`).
- Explicit timeout + background poll on the sentinel.
- Model-agnostic `-m <model>` (excluded models stay summonable ad hoc, e.g.
  outages).

~30 lines of shell for a minimal runner.
