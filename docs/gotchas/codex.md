# Codex CLI

## `codex exec resume` rejects `-s`/`--sandbox`
Symptom: `codex exec resume <sid> -s read-only …` dies with `error: unexpected argument '-s' found` (codex-cli 0.144.1); report never written, but a runner that unconditionally touches its sentinel still signals "done" → caller sees success with a missing report.
Cause: the `-s`/`--sandbox` flag exists on `codex exec` but not on the `resume` subcommand.
Rule: fresh run → `codex exec … -s read-only`; resume → `codex exec resume <sid> -c 'sandbox_mode="read-only"'` (both give the read-only sandbox). Let the sentinel carry the exit code (`echo "${PIPESTATUS[0]}" > sentinel`), never a bare `touch`, so a failed member is detectable.

## Arg-agnostic mocks hide real CLI contracts
Symptom: a bats mock that echoes its args and always exits 0 makes every arg shape pass, so a call the real CLI would reject (see above) stays green until live QA.
Cause: the mock never enforced the real tool's argument rules.
Rule: make mocks reject what the real CLI rejects (mirror its error + exit code), and live-verify each new codex arg shape once before trusting it in tests.

## workspace-write live results (codex-cli 0.144.1, 2026-07-12)
Verified against the real CLI (authed, gpt-5.6-sol) via `codex-exec.sh run --sandbox workspace-write --workdir <repo>`.

- File writes work: fresh run created `hello.txt`; resume run appended to it. Both landed in the worktree. Sentinel `0`.
- Arg shapes accepted live: fresh `-s workspace-write`; resume `-c 'sandbox_mode="workspace-write"'` (resume + write proven). `--workdir` cd is honored.
- `git add`/`git commit` BLOCKED: `.git` is a protected control dir (also `.codex`, `.agents`) — read-only under workspace-write even when its parent is writable. Error: `fatal: Unable to create '.git/index.lock': Operation not permitted`. No flag lifts it in 0.144.1 (`--add-dir` does not help; opt-in is open codex issue #14338). Same block on fresh and resume.
- Commit-author shape: N/A — codex never produces a commit. Orchestrator must `git add`/`git commit` the diff; the commit carries the orchestrator's git identity.
- Network BLOCKED by default: `gh --version` works (local binary, v2.96.0) but `git ls-remote https://github.com/...` fails `Could not resolve host: github.com`. No push/fetch/PR from inside the sandbox.
- Design implication: codex write-mode = edit worktree files + run local tests only. Claude commits, pushes, and (if the sandbox blocked test runs) re-verifies before Ship.

> Note: the auto_review machinery below was superseded by the yolo ruling
> (docs/DECISIONS.md, 2026-07-13 — codex runs `danger-full-access`). These
> entries stay because the live-verified codex facts remain true and hard-won.

## auto_review escalations execute headless (codex-cli 0.144.1, 2026-07-13)
Verified against the real CLI (authed, gpt-5.6-sol) in a throwaway git repo under `/private/tmp`, config `-s workspace-write -c approval_policy="on-request" -c approvals_reviewer="auto_review" -c auto_review.policy="<rendered template>"`.

- FRESH `codex exec`: escalated `gh api --method GET repos/<o>/<r>` executed with exit 0 (network read succeeded, no denial). Inline `auto_review.policy` (a `jq -Rs .` JSON string) accepted.
- RESUME `codex exec resume <sid> -c auto_review.policy=… -c 'sandbox_mode="workspace-write"'`: same escalated read executed, exit 0. Inline policy accepted on resume too. (`resume` still rejects `-s` — set sandbox via `-c sandbox_mode`.)
- PAT isolation (`GH_TOKEN` + isolated `HOME`/`GH_CONFIG_DIR` + `-c shell_environment_policy.include_only=[…]`): NOT live-verified — `externalAgents.codexPatService` is unset on this host (opt-in). Runner and canary injection are unit-tested only; live env-passthrough verification is still pending a configured PAT.

## `--strict-config` validates the WHOLE config.toml, not just `-c` overrides
Symptom: `codex exec --strict-config …` dies before running with e.g. `Error loading config.toml: …:9:1: unknown configuration field 'mcp_servers.pencil.type'`. codex never starts; nothing escalates.
Cause: `--strict-config` strict-validates the entire merged config, including the user's pre-existing `~/.codex/config.toml`. Any field this CLI version rejects (here an MCP-server `type = "stdio"` key) fails the whole load. The spec assumed `--strict-config` only guards our `-c` keys; it does not.
Rule: `--strict-config` is DROPPED (ruling 2026-07-13). It made the canary/gate unrunnable on any config carrying MCP servers or other unknown fields (canary failed closed → exit 3 → advisory fallback). Isolated `CODEX_HOME` was rejected too — it breaks codex login. The typo footgun it was meant to catch is now covered by the canary's exit-0 check: a dropped/mistyped approval key lets the escalation run but fail, which the canary detects deterministically.

## Escalated commands are shell-wrapped; "never" denial string is not universal
- codex emits `command_execution` items as `/bin/zsh -lc '<cmd>'`, not the bare command. Prefix-anchored matching misses them — `audit` and the canary match the tool token as a SUBSTRING (`*"gh "*`, `*"git commit"*`).
- The exact string `Approval policy is currently never` only appears when `approval_policy` is effectively `never`. Under our `approval_policy="on-request"` with NO `approvals_reviewer`, the escalation is SILENTLY denied: the command still runs but its network/`.git` action fails (`error connecting to api.github.com`, exit 1). So denial-string detection alone is insufficient — the canary PASS check must require the privileged command to exit 0, not merely to have executed. Live: auto_review on → gh exit 0; control (no reviewer) → gh exit 1.

## codex escalates ONLY when the prompt asks for it
Symptom: a correct config + rendered policy still fails the canary — codex runs the command in-sandbox and its `.git`/network action fails, even though escalations are active.
Cause: codex requests an approval only when the PROMPT explicitly tells it to use escalated permissions. A bare `Run this command: <cmd>` prompt runs sandboxed and never triggers the reviewer. Live evidence: QA 2026-07-13 — both canaries failed closed with a bare-command prompt; the identical command + policy passed once the prompt began "The sandbox blocks <git writes|network>. Using your shell tool's escalated-permissions mechanism (request approval with a justification), run exactly this one command …".
Rule: the canary — and any escalation-dependent prompt — must state the sandbox limit and explicitly ask codex to request escalated permissions with a justification. Config being correct is not enough.
