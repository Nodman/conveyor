---
name: writing-plans
description: Use after a spec is approved to produce the implementation plan in docs/plans/. TDD task list, exact paths, real code.
---

# Writing plans

Input: an approved spec. Output: `docs/plans/YYYY-MM-DD-<topic>.md`, committed.
Assume the implementer is skilled but has zero context for this codebase.

Header: goal (one sentence), architecture (2-3 sentences), global constraints
(exact values from the spec, one line each).

**File map first.** List every file created/modified and its single
responsibility. Lock decomposition here, not during implementation.

**Tasks.** A task = the smallest unit worth a reviewer's gate, with its own
test cycle. Fold scaffolding into the task that needs it. Per task:
- Files (exact paths), Interfaces (exact names/signatures consumed from
  earlier tasks and produced for later ones).
- TDD steps (checkbox each): write failing test (real code in the plan) → run,
  verify fail → minimal implementation (real code) → run, verify pass →
  commit (exact message). TDD n/a → say why, verification step instead.

**No placeholders.** "TBD", "handle errors appropriately", "similar to task
N", tests without code — plan failures. Fix before presenting.

Self-review against the spec: every requirement maps to a task; names/types
consistent across tasks. Fix inline.

Board mapping: multi-PR plans → one `agent-task` issue per PR-sized slice
(gh issue create), cards to Ready for dev with Priority. Single-PR plans →
straight to conveyor:executing-tasks.

Hand off: offer execution (conveyor:executing-tasks).
