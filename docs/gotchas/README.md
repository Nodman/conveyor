# Gotchas index

One line per trap: `- <category>: <trap title>`.
Full entries live in `<category>.md` files beside this one, added via the conveyor gotchas skill.
- codex: `codex exec resume` rejects `-s`/`--sandbox`
- codex: Arg-agnostic mocks hide real CLI contracts
- codex: `--strict-config` validates the whole config.toml (breaks on user MCP-server fields)
- codex: Escalated commands are shell-wrapped; the "never" denial string is not universal
- github-api: Projects item-list lags item-add
- bats: Mid-test `[[ ]]` assertion failures do not fail the test
- worktrees: Shell cwd persists — a `cd` into a worktree leaks into later commands
