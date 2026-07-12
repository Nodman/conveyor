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
