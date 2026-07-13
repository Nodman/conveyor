# Plan: codex native gate (auto_review)

**Goal:** implement docs/specs/2026-07-13-codex-native-gate.md — codex runs with
native escalation approvals (deny-by-default policy), posts its own reviews,
commits locally; orchestrator keeps publication.

**Architecture:** all mechanism lives in `codex-exec.sh` (render policy → inject
config → canary → audit) plus trusted policy templates under `plugin/config/`.
Skill/agent markdown then re-describes the lanes. Two PR slices: (1) runner
machinery + tests, (2) skill/doc rewrites + version bump.

**Global constraints:**
- Sandbox allowlist stays `read-only|workspace-write`; sentinel = codex exit only.
- bats runs macOS bash 3.2 (no mapfile; heredoc/apostrophe trap — see running-tests skill).
- Mocks must reject what the real CLI rejects (docs/gotchas/codex.md).
- Canary denial string is exactly: `Approval policy is currently never`.
- Every new codex arg shape gets ONE live verification, recorded in gotchas.

## File map

| File | Responsibility |
|---|---|
| `plugin/scripts/codex-exec.sh` | +`render-policy`, `run --role/--pr/--issue/--output-schema`, `preflight --escalations`, `audit` |
| `plugin/config/codex-policies/exec.policy.txt` | executor escalation policy template (UPPERCASE placeholders) |
| `plugin/config/codex-policies/review.policy.txt` | reviewer escalation policy template |
| `plugin/config/codex-policies/report.schema.json` | `--output-schema` report shape (verdict, privileged_actions, denials, commit_shas, tests) |
| `tests/codex-exec.bats` | new cases: render, role injection, canary, audit |
| `tests/helpers/bin/codex` | stub: `--strict-config` key validation, escalation fixtures |
| `tests/helpers/bin/security` | stub for keychain lookup (PAT opt-in) |
| `plugin/agents/pr-reviewer.md` | transport-neutral charter, Escalations report section |
| `plugin/skills/executing-tasks/SKILL.md` | local commits, pre-push judgment, codex full gate |
| `plugin/skills/routing/SKILL.md` + `references/*` | drop read-only constraint; canary gate; friction notes |
| `plugin/skills/council/SKILL.md` | `--workdir` on run lines |
| `docs/gotchas/codex.md` | auto_review live results, denial string, typo footgun, filters risk |
| `plugin/.claude-plugin/plugin.json` | patch bump (each PR) |

## PR 1 — runner machinery

### Task 1: policy templates + `render-policy`

Files: `plugin/config/codex-policies/{exec,review}.policy.txt`, `codex-exec.sh`.
Interface: `codex-exec.sh render-policy <exec|review> --name N --workdir D [--pr N --issue N]` → rendered text on stdout; dies on leftover placeholder.

- [ ] Failing test (`tests/codex-exec.bats`):
```bats
@test "render-policy: review fills every placeholder" {
  use_cfg
  run bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' render-policy review \
    --name codex-gpt-5.6-sol--12-1 --pr 12 --issue 7 --workdir '$TMP'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex-gpt-5.6-sol--12-1"* ]]
  run grep -cE '(AGENT_NAME|OWNER|REPO|PR_NUMBER|ISSUE_NUMBER|WORKTREE|LABEL_APPROVED)' <<<"$output"
  [ "$output" = "0" ]
}
@test "render-policy: review without --pr dies" {
  use_cfg
  run -2 bash -c "cd '$TMP' && '$SCRIPTS/codex-exec.sh' render-policy review --name x --workdir '$TMP'"
}
```
- [ ] Run `bats tests/codex-exec.bats` — both fail (no subcommand).
- [ ] Implement: templates carry the spec's policy text with `AGENT_NAME OWNER REPO
  PR_NUMBER ISSUE_NUMBER WORKTREE LABEL_APPROVED` placeholders;
```bash
render_policy() { # role name workdir pr issue
  local tpl="$SCRIPT_DIR/../config/codex-policies/$1.policy.txt"
  [[ -f "$tpl" ]] || die "no policy template: $tpl"
  [[ "$1" == exec || ( -n "$4" && -n "$5" ) ]] || die "render-policy review needs --pr and --issue"
  sed -e "s|AGENT_NAME|$2|g" -e "s|WORKTREE|$3|g" -e "s|PR_NUMBER|$4|g" \
      -e "s|ISSUE_NUMBER|$5|g" -e "s|OWNER|$(cfg .owner)|g" \
      -e "s|REPO|$(cfg .repo)|g" -e "s|LABEL_APPROVED|$(cfg '.labels.approved')|g" "$tpl"
}
```
- [ ] Run — pass. Commit: `feat(codex-exec): policy templates + render-policy subcommand`

### Task 2: `run --role` config injection + `--output-schema`

Files: `codex-exec.sh` (run_codex arg loop, runner heredoc), `tests/helpers/bin/codex`.
Interface: `run … --role exec|review [--pr N --issue N] [--output-schema F]`; role adds
`--strict-config -c approval_policy -c approvals_reviewer -c auto_review.policy` to
BOTH fresh and resume command lines; policy JSON is `jq -Rs .` of the rendered text,
written next to the report (`<out>.policy.json`) and injected in the runner via
`-c "auto_review.policy=$(cat <file>)"` (no quoting fights in the heredoc).

- [ ] Failing test:
```bats
@test "run --role review writes approval config into the runner" {
  use_cfg
  echo hi > "$TMP/p.md"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-gpt-5.6-sol \
    --model gpt-5.6-sol --sandbox workspace-write --workdir '$TMP' --role review \
    --pr 12 --issue 7 --output-schema '$SCRIPTS/../config/codex-policies/report.schema.json' \
    --out '$TMP/r.md' --prompt-file '$TMP/p.md' --visibility background"
  [ "$status" -eq 0 ]
  grep -q -- '--strict-config' "$TMP/r.run.sh"
  grep -q 'approvals_reviewer="auto_review"' "$TMP/r.run.sh"
  grep -q 'auto_review.policy=' "$TMP/r.run.sh"
  grep -q -- '--output-schema' "$TMP/r.run.sh"
  [ -f "$TMP/r.policy.json" ]
}
```
- [ ] Verify fail; implement; verify pass. Stub `codex` gains `--strict-config`:
  with it, any `-c key=…` outside a known-key list exits 1 (mirrors real CLI).
- [ ] Commit: `feat(codex-exec): --role escalation config + --output-schema passthrough`

### Task 3: canary preflight

Files: `codex-exec.sh` (preflight), stub codex, `tests/codex-exec.bats`.
Interface: `preflight --escalations <role>` → runs one fixture escalation in a temp
dir with the exact production config; PASS = privileged command executed; seeing
`Approval policy is currently never` → exit 3 + message naming the fix; result
cached at `.conveyor/canary/<role>.<cli-version>.<policy-sha>` for the session.

- [ ] Failing tests:
```bats
@test "preflight --escalations exec passes and caches" {
  use_cfg
  run bash -c "cd '$TMP' && CODEX_STUB_ESCALATION=ok $CX '$SCRIPTS/codex-exec.sh' preflight --escalations exec"
  [ "$status" -eq 0 ]
  run bash -c "ls '$TMP/.conveyor/canary/' | wc -l"; [ "${output// /}" = "1" ]
}
@test "preflight --escalations detects silent denial" {
  use_cfg
  run -3 bash -c "cd '$TMP' && CODEX_STUB_ESCALATION=denied $CX '$SCRIPTS/codex-exec.sh' preflight --escalations exec"
  [[ "$output" == *"auto_review not active"* ]]
}
```
- [ ] Stub: `CODEX_STUB_ESCALATION=ok` emits a JSONL `command_execution` for
  `git commit --allow-empty` with exit 0; `denied` emits an `agent_message`
  containing the denial string. Implement; pass.
- [ ] Commit: `feat(codex-exec): escalation canary preflight with session cache`

### Task 4: `audit` subcommand

Interface: `codex-exec.sh audit <log>` → one line per privileged
`command_execution` (`gh `, `git commit`, `curl`, `wget`, `nc `, `ssh `):
`<exit_code>\t<command>`; exit 0 with `none` when empty.

- [ ] Failing test (fixture `tests/fixtures/codex-escalated.log` with one `gh api` line, one `ls` line):
```bats
@test "audit extracts privileged commands only" {
  use_cfg
  run bash -c "'$SCRIPTS/codex-exec.sh' audit '$BATS_TEST_DIRNAME/fixtures/codex-escalated.log'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gh api"* ]]
  [[ "$output" != *"ls -la"* ]]
}
```
- [ ] Implement with jq over `item.completed`/`command_execution` items; pass.
- [ ] Commit: `feat(codex-exec): audit subcommand for inferred-escalation reconciliation`

### Task 5: opt-in PAT env

Interface: config key `externalAgents.codexPatService` (keychain service name).
Present → runner exports `GH_TOKEN="$(security find-generic-password -s <svc> -w)"`,
`GH_CONFIG_DIR=<run-dir>/ghcfg`. Absent → no-op.

- [ ] Failing test (add `tests/helpers/bin/security` stub echoing `stub-pat`):
```bats
@test "run --role review with codexPatService isolates gh auth" {
  use_cfg
  jq '.externalAgents.codexPatService = "conveyor-codex"' "$TMP/.claude/conveyor.json" > "$TMP/c.json"
  mv "$TMP/c.json" "$TMP/.claude/conveyor.json"
  echo hi > "$TMP/p.md"
  run bash -c "cd '$TMP' && $CX '$SCRIPTS/codex-exec.sh' run --name codex-x --model m \
    --sandbox workspace-write --workdir '$TMP' --role review --pr 1 --issue 1 \
    --out '$TMP/r.md' --prompt-file '$TMP/p.md' --visibility background"
  grep -q 'GH_TOKEN=' "$TMP/r.run.sh"
  grep -q 'GH_CONFIG_DIR=' "$TMP/r.run.sh"
}
```
- [ ] Implement; pass. Commit: `feat(codex-exec): opt-in repo-scoped PAT via keychain lookup`

### Task 6: live verification (TDD n/a — real CLI runbook)

TDD n/a: these prove real-CLI arg shapes, which stubs cannot.
- [ ] `render-policy review … | jq -Rs .` → fresh `codex exec --strict-config -c auto_review.policy=…`
  canary run in a scratch repo: escalated `gh api --method GET repos/<o>/<r>` executes.
- [ ] Same via `codex exec resume <sid> -c …` — inline policy accepted on resume.
- [ ] If PAT configured: env passthrough carries `GH_TOKEN` into escalated command.
- [ ] Record all three (+ any surprises) in `docs/gotchas/codex.md`; adjust templates if the
  reviewer over/under-approves the canary.
- [ ] Gate: `bats tests` + shellcheck green. Commit: `docs(gotchas): auto_review live verification results`

## PR 2 — skills, agents, docs

### Task 7: charter + skill rewrites (TDD n/a — markdown; verify = structure.bats + review)

- [ ] `plugin/agents/pr-reviewer.md`: codex transport posts directly (policy-bound);
  card moves reported, not executed; mandatory Escalations section in the report.
- [ ] `plugin/skills/executing-tasks/SKILL.md`: codex lane commits locally
  (COMMIT_SAFE pre-checks: hooks, hooksPath, filters, submodules → else orchestrator
  commits); judgment moves pre-push; Ship spawns the gate with `--role review
  --pr <n> --issue <n>` after `preflight --escalations review`; advisory flow
  becomes the canary-fail fallback; `audit <log>` + GitHub reconciliation step
  after every codex run (mismatch → pull approved-by-agent, fresh review).
- [ ] `plugin/skills/routing/SKILL.md`: drop "isolated implementation or read-only
  review" constraint; direct lane requires passed canary. `references/model-pool.md`:
  codex control note → "native escalations (auto_review); no live steering;
  inferred-approval audit". `references/delegation-contract.md`: config shape,
  resume form, policy hash, canary, report fields.
- [ ] `plugin/skills/council/SKILL.md`: add `--workdir <repo root>` to both run lines.
- [ ] `plugin/.claude-plugin/plugin.json`: patch bump.
- [ ] Verify: `bats tests` green; re-read each file against the spec's Decisions list.
- [ ] Commit: `docs(skills): codex native gate — direct review/commit lanes, canary gating`

## Board mapping

Multi-PR plan → two `agent-task` issues (Ready for dev, P2):
- S1 "codex-exec: auto_review machinery (render/role/canary/audit/PAT)" — PR 1, Tasks 1-6.
- S2 "skills/docs: codex native gate lanes" — PR 2, Task 7; depends on S1 merge.

Both issues link this plan + the spec.
