---
name: brainstorming
description: Use when a human asks for new work — features, changes of behavior, new components — BEFORE any implementation. Q&A → design → approved spec in docs/specs/. Scale to task size.
---

# Brainstorming

Hard gate: no implementation, scaffolding, or code before the user approves a
design. Scale the process, not the gate: a trivial fix needs one clarifying
question and a two-sentence design; a feature needs the full flow.

0. **Doctor.** In a conveyor repo (`.claude/conveyor.json` exists), run
   /conveyor:doctor first if it hasn't run this session.
1. **Context.** Read the relevant code/docs first (delegate exploration for
   anything over a few files). Check docs/DECISIONS.md and docs/gotchas/.
2. **Questions — one at a time.** Prefer multiple-choice (AskUserQuestion).
   Aim at purpose, constraints, success criteria. Stop asking when answers
   stop changing the design.
3. **Approaches.** Present 2-3 with trade-offs; lead with your recommendation.
4. **Design.** Present in sections scaled to complexity; get approval per
   section for large designs, one approval for small ones. Cover: what/why,
   components, data flow, error handling, testing.
5. **Spec.** Write `docs/specs/YYYY-MM-DD-<topic>.md`: What, Why, Decisions
   (locked), Design, Out of scope. Condensed — bullets over prose.
   Self-review: placeholders? contradictions? two-way-interpretable
   requirements? single-plan scope? Fix inline, then commit.
6. **User gate.** Ask the user to review the spec file. Approved → invoke
   conveyor:writing-plans. Nothing else follows brainstorming.

Multi-subsystem requests: decompose FIRST (one spec each), brainstorm the
first subsystem, queue the rest as board issues.
