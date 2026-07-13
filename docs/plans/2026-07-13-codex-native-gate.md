# Plan: codex direct lane (yolo)

**Rewritten 2026-07-13 after the yolo ruling** — the original auto_review plan
(Tasks 1-7: policies, render-policy, canary, PAT) is superseded; its
implementation history lives in PR #65's early commits and docs/DECISIONS.md.

**Goal:** docs/specs/2026-07-13-codex-native-gate.md — codex unsandboxed,
structural guards, reviewer ladder unchanged.

**Global constraints:** bats on macOS bash 3.2; mocks reject what the real CLI
rejects; sentinel = codex exit only; CI must be green (gh pr checks), not just
local bats — background-runner tests must not race teardown.

## S1 (PR #65, slimmed) — runner

| Keep | Delete |
|---|---|
| `--output-schema` passthrough (fresh+resume) + tests | render-policy + templates + tests |
| `audit <log>` + fixture tests | preflight --escalations canary + tests |
| stub codex `--version`, strict-config capability | PAT env plumbing (`pat_exports`, `codexPatService`, security stub) + tests |
| gotchas records (all — they are true) | escalation stub fixtures, CODEX_STUB_PROMPT_CAPTURE test |
| report schema → `plugin/config/report.schema.json` | `plugin/config/codex-policies/` dir |

Plus: sandbox allowlist accepts `danger-full-access` (maps to
`-s danger-full-access`; resume via `-c 'sandbox_mode="danger-full-access"'`),
with a bats case asserting the runner text for both fresh and resume; usage
text updated; gotchas gains one line pointing the auto_review entries at the
DECISIONS ruling. plugin.json stays 0.1.21. Verify: bats + shellcheck green
locally AND `gh pr checks 65` green after push.

## S2 (issue #64) — skills/docs

Rewrite per the spec's Design list: executing-tasks (codex full-access lane,
codex pushes its branch, orchestrator CI-watch after every push, proportional
claude-lane pre-push skim), routing SKILL + model-pool + delegation-contract
(drop read-only constraint; friction note "full access; no mid-run steering;
audit post-hoc"), doctor (warn when `main` lacks branch protection),
pr-reviewer (codex gate posts directly), council --workdir fix. Patch bump.

Board: S1 = PR #65 (in flight); S2 = issue #64 (Ready for dev, blocked on S1
merge).
