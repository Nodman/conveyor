---
name: council
description: Use when the human explicitly convenes the council — deep multi-model deliberation on a hard design question. Independent proposals → one rebuttal round → merged verdict → normal spec flow. Heavier than brainstorming; never auto-invoke.
---

# /conveyor:council

Deliberation only: members research and argue, nobody edits files. Scripts
live in `${CLAUDE_PLUGIN_ROOT}/scripts/`.

## Setup

- `codex-exec.sh preflight` — failure → report it, offer plain
  conveyor:brainstorming instead.
- Members: `jq -c '.council.members // [{"runner":"claude","model":"fable-5"},{"runner":"codex","model":"gpt-5.6-sol"}]' .claude/conveyor.json`
- Names are always `<runner>-<model>` (e.g. `claude-fable-5`,
  `codex-gpt-5.6-sol`) — in Agent names, report files, and every mention to
  the user. Future runners follow the same rule.
- `codex-exec.sh detect` → `unset` → AskUserQuestion (spawn external agents
  in a separate window / keep in background) → `codex-exec.sh set-visibility
  <window|background>`, then continue.
- Artifacts: `<scratchpad>/council/` — prompt files, reports, logs. Paths
  must not contain spaces.

## Flow

1. **Frame.** Short Q&A (brainstorming style, scaled down) until the design
   question is one unambiguous paragraph. Include success criteria.
2. **Round 1 — proposals.** Identical brief for every member: the question,
   repo root path, pointers (CLAUDE.md, docs/specs/, docs/DECISIONS.md), and
   the report contract — condensed bullets, `file:line` refs, ONE recommended
   design plus alternatives rejected with reasons. Launch all members in
   parallel:
   - claude runner → Agent tool, `name: claude-<model>`, `model:` the config
     value up to the first dash (`fable-5` → `fable`), read-only instructions.
   - codex runner → `codex-exec.sh run --name codex-<model> --model <model>
     --workdir <repo root> --out <dir>/<name>-r1.md --prompt-file
     <dir>/<name>-r1-prompt.md`. Deliberation-only is enforced by the
     prompt, not a sandbox — codex runs full-access (yolo ruling) so it
     can research the web.
   Wait: `codex-exec.sh wait <out> --timeout 540` per codex member (re-call
   once for the 15-min cap; claude members return via Agent). `dead`/timeout
   → `codex-exec.sh kill <out>`, drop that member and tell the user.
3. **Round 2 — rebuttal.** Each member receives all other proposals verbatim:
   "Attack or concede each point. Concede only what is genuinely better.
   End with your revised proposal." claude runners → SendMessage to the named
   agent; codex runners → `codex-exec.sh run --resume "$(codex-exec.sh
   session-id <dir>/<name>-r1.log)" --workdir <repo root> --out
   <dir>/<name>-r2.md …`. Resume is always by explicit session id.
4. **Verdict.** You (main session) judge the revised proposals: points of
   agreement are settled; disagreements you resolve with stated reasoning;
   merge the strongest parts into one design. Present: verdict, then a short
   "who argued what" trace naming each member.
5. **Hand-off.** One member left after failures → say the council degraded to
   a deep brainstorm. On user approval of the verdict, continue with
   conveyor:brainstorming steps 5–6 (spec + user gate); the spec records the
   condensed verdict and member positions. Raw artifacts stay in scratch.
