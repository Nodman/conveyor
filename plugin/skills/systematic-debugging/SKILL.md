---
name: systematic-debugging
description: Use on any bug, test failure, or unexpected behavior BEFORE proposing fixes. Root cause first; no fix without a reproduction.
---

# Systematic debugging

Phase 1 — **Reproduce & read.** Reproduce the failure deterministically. Read
the ENTIRE error output — the answer is usually in it. No reproduction → you
are not debugging yet, you are guessing.

Phase 2 — **Trace to root cause.** Follow the failure backwards (stack, data
flow, recent diff — `git log -p` the touched area). Name the root cause in one
sentence. "I think" is not a root cause; verify by inspection or logging.

Phase 3 — **Hypothesis → minimal experiment.** One hypothesis, the smallest
change/probe that confirms or kills it. Confirmed → phase 4. Killed → next
hypothesis. Never stack speculative changes.

Phase 4 — **Fix at the root + pin it.** Fix the cause, not the symptom.
Add the regression test that would have caught it (TDD skill). Remove the
probes. If the trap was non-obvious → gotchas skill.

Escalation rule: **3 failed fixes → stop.** The problem is your model of the
system, not the code. Re-derive assumptions from scratch; question the
architecture; consider that the bug is somewhere you have not looked.
