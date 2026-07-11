# Codex CLI

## `codex exec resume` rejects `-s`/`--sandbox`
Symptom: `codex exec resume <sid> -s read-only …` dies with `error: unexpected argument '-s' found` (codex-cli 0.144.1); report never written, but a runner that unconditionally touches its sentinel still signals "done" → caller sees success with a missing report.
Cause: the `-s`/`--sandbox` flag exists on `codex exec` but not on the `resume` subcommand.
Rule: fresh run → `codex exec … -s read-only`; resume → `codex exec resume <sid> -c 'sandbox_mode="read-only"'` (both give the read-only sandbox). Let the sentinel carry the exit code (`echo "${PIPESTATUS[0]}" > sentinel`), never a bare `touch`, so a failed member is detectable.

## Arg-agnostic mocks hide real CLI contracts
Symptom: a bats mock that echoes its args and always exits 0 makes every arg shape pass, so a call the real CLI would reject (see above) stays green until live QA.
Cause: the mock never enforced the real tool's argument rules.
Rule: make mocks reject what the real CLI rejects (mirror its error + exit code), and live-verify each new codex arg shape once before trusting it in tests.
