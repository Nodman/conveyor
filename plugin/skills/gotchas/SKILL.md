---
name: gotchas
description: Use before modifying any subsystem (consult recorded traps) and immediately after discovering a trap — code that looks right but fails non-obviously. Reads/writes docs/gotchas/.
---

# Gotchas protocol

**Consult** (before touching an area): read `docs/gotchas/README.md` — it is a
one-line-per-trap index. Open the category file for anything touching your
area. No README → nothing recorded yet, proceed.

**Record** (the moment a trap is confirmed, not at PR time):
1. Pick the category file `docs/gotchas/<category>.md` — reuse an existing
   category if one fits, create a new one if not (kebab-case, by subsystem or
   technology, e.g. `swiftui.md`, `auth.md`, `ci.md`).
2. Append an entry: `## <one-line trap title>` then 2-4 lines:
   symptom → root cause → the rule to follow. Condensed; no narrative.
3. Add ONE line to `docs/gotchas/README.md` index: `- <category>: <trap title>`.

**What qualifies:** something that *looks correct and fails non-obviously* —
API misbehavior, ordering constraints, environment quirks. Regular bugs,
style issues, and one-off typos do NOT qualify.

Rulings ("we chose X over Y") are not gotchas — those go to `docs/DECISIONS.md`.
