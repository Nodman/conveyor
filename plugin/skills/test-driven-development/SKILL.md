---
name: test-driven-development
description: Use when implementing any feature or bugfix that has a testable seam, before writing implementation code. Red → green → refactor.
---

# TDD

The loop, per behavior:
1. **Red** — write ONE failing test for the next behavior. Run it. It must
   fail for the RIGHT reason (missing behavior, not a typo/import error).
2. **Green** — write the minimum code that passes. Run the test. Passes.
3. **Refactor** — clean up with tests green. Run the full touched suite.
4. Commit. Next behavior.

Rules:
- Test the behavior, not the implementation. One behavior per test; exact
  expected values, not broad "not null" assertions.
- Never weaken, skip, or delete a failing test to get to green — fix the code,
  or if the test is genuinely wrong, say so explicitly and fix the test as its
  own step.
- Bugfix = first a test that reproduces the bug, then the fix.
- The failing run in step 1 is not optional — a test you never saw fail proves
  nothing.

**When TDD does not apply** (no testable seam: pure config, docs, prompt
files, throwaway scripts): say so explicitly in one line ("TDD n/a: <reason>")
and proceed. Verification then = running the real thing once and observing.
