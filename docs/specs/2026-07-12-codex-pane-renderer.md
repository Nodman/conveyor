# Codex pane: placement, title, condensed JSONL renderer

## What

Fix the three UX problems of external codex agent panes spawned by
`plugin/scripts/codex-exec.sh`:

- pane opens below the current pane → open to the right (40% width)
- pane shows the raw verbose `codex exec` stream → condensed activity feed
- output is plain white → semantic colors, in fresh AND resume runs
- pane border shows hostname → show the agent name (`<runner>-<model>`)

## Why

- Council run (2026-07-12, members `claude-fable-5`, `codex-gpt-5.6-sol`)
  unanimous after rebuttal; verdict validated by 8 live demos, user approved.
- Root causes (live-verified, codex-cli 0.144.1, tmux 3.7b):
  - `tmux split-window -d -v -l 15` explicitly requests a 15-line lower pane.
  - `codex exec` defaults to `--color auto`; the `| tee` pipe is not a TTY →
    colors off.
  - No codex flag condenses the human stream (same task: 164 log lines native
    vs 12 as JSONL; a real council run logged 2,791 lines).
  - `codex exec resume` rejects `--color` outright → the minimal
    `--color always` fix can never color the resume path, and it breaks the
    `session_id()` grep (colored header starts with ESC byte — verified).

## Decisions (locked)

- **JSONL renderer, not native stream**: `--json` on fresh and resume
  (both shapes live-verified), rendered by a new internal `render`
  subcommand in `codex-exec.sh`. Bash + `jq` only (jq already required).
- **Log becomes machine-clean**: raw JSONL + one synthetic plain
  `session id: <thread_id>` line. `session_id()` stays byte-identical.
- **No resume seeding**: resume re-emits `thread.started` with the same
  thread id (live-verified) — one code path for fresh and resume.
- **No diff content in the pane**: `file_change` events carry kind + path
  only. Diff review happens in git/PR. Deferred, not designed around.
- **Pane title = agent name** (`--name` arg, e.g. `codex-gpt-5.6-sol`):
  user's tmux displays pane titles; call is harmless where hidden.
  Never asserted as visible in tests.
- **Renderer must be crash-proof**: a display bug must not SIGPIPE-kill the
  codex run (renderer is the last pipe stage in every visibility mode).

## Design

### Spawn (tmux case, `run_codex`)

```bash
pane="$(tmux split-window -d -h -l 40% -P -F '#{pane_id}' "$runner")"
tmux select-pane -t "$pane" -T "$name"
```

Keep `-d` and the 10s linger. window/background modes unchanged.

### Spawn (iterm case)

Same below-instead-of-right bug: iTerm2's `split horizontally` = horizontal
divider = new pane below. Change to `split vertically` and name the session:

```applescript
tell application "iTerm2" to tell current session of current window
  set newSession to (split vertically with default profile command "$runner")
end tell
tell newSession to set name to "$name"
```

(one osascript invocation; exact quoting worked out in the plan). iTerm rung
is untested on this machine — verify manually once during QA, best-effort.

### Runner (all modes, one shape)

```bash
echo "=== $name ==="
# prompt echoed dim so the human sees what the agent was asked
$codex_cmd $sandbox --json -o $out - < $prompt_file 2>&1 | codex-exec.sh render $log
echo "${PIPESTATUS[0]}" > $sentinel
```

- fresh: `codex exec -m $model -s $sandbox_mode`; resume:
  `codex exec resume $sid -c 'sandbox_mode="..."'` — unchanged.
- sentinel keeps codex's exit code via `PIPESTATUS[0]`; `rm -f` of
  out/sentinel before spawn stays.

### `render` subcommand

Hardened loop — structural, not aspirational:

- no `set -e` in the render path; `while IFS= read -r line`
- every raw line appended to `$log` FIRST, before any parsing
- non-JSON line → print dim `! <line>`, continue (codex startup errors
  surface this way — verified with the trusted-directory failure)
- one `jq ... || true` per event; unknown/malformed events: logged, skipped
- on `thread.started`: append synthetic `session id: <thread_id>` to `$log`
  (sole carrier of the resume contract in JSON mode), print bold
- ANSI emitted only when `[[ -t 1 ]]` → panes colored; background stdout
  and the log never see ESC bytes
- after stream ends: print dim `report: $out` once

Display map (one blank line between entries — user request):

| event | pane line |
|---|---|
| `thread.started` | bold `session <id>` |
| `command_execution` started | cyan `$ <command>` (1 line, output never shown) |
| `command_execution` failed | red `! exit <code>: <command>` |
| `file_change` | green `✓ <kind> <path>` per file; path relative to workdir (events carry absolute paths — verified; shape: `.item.type == "file_change"`, `.item.changes[]`) |
| `agent_message` | cyan, full text, no truncation (interim + final) |
| `reasoning` | dim, single line, whitespace-folded, capped ~160 chars |
| `todo_list` | dim `→ <first unfinished step>` |
| `turn.completed` | green `✓ done · <in> in · <out> out` (codex-side tokens, info only) |
| `error` | red `✖ <message>` |

Prompt visibility: the runner prints the prompt file dim between header and
codex output (`--json` does not echo the prompt — verified).

### Tests (`tests/codex-exec.bats`, mock `tests/helpers/bin/codex`)

- mock emits representative JSONL under `--json` (thread.started, command,
  file_change with absolute-path `changes[]`, agent_message, turn.completed);
  keeps rejecting resume + `-s` and gains rejecting resume + `--color`
- fresh and resume runner scripts contain `--json` and `-o`
- log contains exactly one `^session id: ` line and zero ESC bytes
- renderer fed a garbage/non-JSON line and an unknown event type: survives,
  sentinel still carries codex's (nonzero) exit code
- tmux mock records `split-window -d -h -l 40%`; title call present but
  visibility never asserted
- update existing assertions: `tests/codex-exec.bats:95-104` (split args),
  plain session fixture at `:60` stays valid

### Rollout

- patch version bump in `plugin/.claude-plugin/plugin.json` (repo law)
- live smoke before merge: one real fresh + one real resume run through the
  new runner (docs/gotchas/codex.md doctrine: live-verify every new codex
  arg shape) — both shapes already probed once during the council

## Out of scope

- rendering diff/patch content in the pane (revisit if codex JSONL exposes it)
- pane placement/width configurability (`-b` left, config key)
- Terminal.app (window mode) titles
- codex JSONL schema-drift handling beyond log-and-skip
- suppressing codex reasoning via config (`hide_agent_reasoning`) — moot
  under the renderer

## Council record

- `claude-fable-5` r1: minimal `--color always` + ANSI-strip `session_id()`;
  rejected renderer as complexity. r2: conceded renderer core after live
  probes (`--json` kills the `session id:` header; resume accepts `--json`,
  re-emits same thread id); contributed SIGPIPE hardening, dropped seeding.
- `codex-gpt-5.6-sol` r1: JSONL renderer architecture, `-h -l 40%`. r2:
  conceded tmux one-liner, `script`/process-substitution rejections, dropped
  pane-title assertion; kept resume seeding (overruled — verified redundant).
- Verdict: codex architecture + claude hardening. Demos added: prompt echo,
  full agent messages (no truncation), single trailing report line, relative
  file paths, blank line between entries.
