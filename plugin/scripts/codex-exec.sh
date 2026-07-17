#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugin/scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

usage() {
  {
    echo "usage: codex-exec.sh preflight"
    echo "       codex-exec.sh detect"
    echo "       codex-exec.sh set-visibility <window|background>"
    echo "       codex-exec.sh session-id <log>"
    echo "       codex-exec.sh run --name <runner-model> --model <m> --out <report.md> --prompt-file <f> [--resume <session-id>] [--effort minimal|low|medium|high|xhigh] [--visibility <mode>] [--sandbox read-only|workspace-write|danger-full-access (default: danger-full-access)] [--workdir <dir>] [--output-schema <f>]"
    echo "       codex-exec.sh kill <report.md>"
    echo "       codex-exec.sh status <report.md>"
    echo "       codex-exec.sh wait <report.md> [--timeout <s>]"
    echo "       codex-exec.sh audit <log>"
    echo "       codex-exec.sh render <log> <report> [color-code] (internal: codex --json stream on stdin)"
  } >&2
  exit 2
}

preflight() {
  need codex
  codex login status >/dev/null 2>&1 || die_code3 "codex not authenticated — run: codex login"
  echo ok
}

audit() {
  local log="${1:-}"
  [[ -f "$log" ]] || die "no log file: $log"
  local found="" line t it cmd rc
  while IFS= read -r line; do
    jq -e . >/dev/null 2>&1 <<<"$line" || continue
    t="$(jq -r '.type // empty' <<<"$line" 2>/dev/null)"
    [[ "$t" == item.completed ]] || continue
    it="$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)"
    [[ "$it" == command_execution ]] || continue
    cmd="$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null)"
    rc="$(jq -r '.item.exit_code // 1' <<<"$line" 2>/dev/null)"   # missing exit_code = suspect, not success
    # substring, not prefix: codex wraps commands as `/bin/zsh -lc '<cmd>'`;
    # `*git*commit*` catches the hardened `git -c core.hooksPath=… commit` shape too
    case "$cmd" in
      *"gh "*|*"curl "*|*"wget "*|*"ssh "*|*"scp "*|*"rsync "*|*"nc "*|*"git"*"push"*|*"git"*"fetch"*|*"git"*"commit"*)
        printf '%s\t%s\n' "$rc" "$cmd"; found=1 ;;
    esac
  done < "$log"
  [[ -n "$found" ]] || echo none
}

detect() {
  if [[ -n "${TMUX:-}" ]]; then echo tmux
  elif [[ "${LC_TERMINAL:-}" == "iTerm2" || "${TERM_PROGRAM:-}" == "iTerm.app" ]]; then echo iterm
  else cfg_or '.externalAgents.fallbackVisibility' unset
  fi
}

set_visibility() {
  case "${1:-}" in window|background) ;; *) usage ;; esac
  [[ -f "$CONVEYOR_CONFIG" ]] || die "no $CONVEYOR_CONFIG — run /conveyor:init first"
  local tmp; tmp="$(mktemp)"
  jq --arg v "$1" '.externalAgents.fallbackVisibility = $v' "$CONVEYOR_CONFIG" > "$tmp"
  mv "$tmp" "$CONVEYOR_CONFIG"
  echo "externalAgents.fallbackVisibility=$1"
}

session_id() {
  [[ -f "${1:-}" ]] || die "no log file: ${1:-}"
  grep -m1 '^session id: ' "$1" | awk '{print $3}' | grep . || die "no session id in $1"
}

agent_color() {
  local checksum
  checksum="$(printf '%s' "$1" | cksum)"
  checksum="${checksum%% *}"
  case $((checksum % 4)) in
    0) echo 34 ;;
    1) echo 35 ;;
    2) echo 33 ;;
    3) echo 36 ;;
  esac
}

render_report() {
  # default FG on purpose: report block must stand out from the agent-color wall
  jq -er '
    def list(f): if length == 0 then "none" else map(f) | join("; ") end;
    (.message // empty),
    "verdict: \(.verdict)",
    "tests: \(.tests // [] | list(.))",
    "commits: \(.commit_shas // [] | list(.))",
    "privileged: \(.privileged_actions // [] | list("\(.command) (exit \(.exit_code))"))",
    "denials: \(.denials // [] | list(.))"
  ' <<<"$1" 2>/dev/null
}

render_stream() {
  set +e   # a display bug must never SIGPIPE-kill the codex run
  local log="${1:?}" report="${2:-}" color="${3:-36}"
  local B="" R="" G="" C="" D="" N=""
  if [[ -t 1 ]]; then
    B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; C=$'\e['"$color"m; D=$'\e[2m'; N=$'\e[0m'
  fi
  : > "$log"
  local line type itype txt cmd rc rendered
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$log"
    if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
      printf '%s! %s%s\n\n' "$D" "$line" "$N"
      continue
    fi
    type=$(jq -r '.type // empty' <<<"$line" 2>/dev/null)
    case "$type" in
      thread.started)
        txt=$(jq -r '.thread_id // empty' <<<"$line" 2>/dev/null)
        if [[ -n "$txt" ]]; then
          printf 'session id: %s\n' "$txt" >> "$log"
          printf '%ssession %s%s\n\n' "$B" "$txt" "$N"
        fi ;;
      item.started|item.completed)
        itype=$(jq -r '.item.item_type // .item.type // empty' <<<"$line" 2>/dev/null)
        case "$itype" in
          command_execution)
            cmd=$(jq -r '.item.command // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-120)
            if [[ "$type" == item.started && -n "$cmd" ]]; then
              printf '%s$ %s%s\n\n' "$C" "$cmd" "$N"
            elif [[ "$type" == item.completed ]]; then
              rc=$(jq -r '.item.exit_code // 0' <<<"$line" 2>/dev/null)
              if [[ "$rc" != 0 ]]; then printf '%s! exit %s: %s%s\n\n' "$R" "$rc" "$cmd" "$N"; fi
            fi ;;
          file_change)
            if [[ "$type" == item.completed ]]; then
              jq -r --arg pwd "$PWD/" '.item.changes[]? | "\(.kind) \(.path | ltrimstr($pwd))"' <<<"$line" 2>/dev/null |
                while IFS= read -r txt; do printf '%s+ %s%s\n' "$G" "$txt" "$N"; done
              printf '\n'
            fi ;;
          agent_message)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null)
              if [[ -n "$txt" ]]; then
                if jq -e '.verdict? // empty | length > 0' >/dev/null 2>&1 <<<"$txt" && rendered=$(render_report "$txt"); then
                  printf '%s\n\n' "$rendered"
                else
                  printf '%s%s%s\n\n' "$C" "$txt" "$N"
                fi
              fi
            fi ;;
          reasoning)
            if [[ "$type" == item.completed ]]; then
              txt=$(jq -r '.item.text // empty' <<<"$line" 2>/dev/null | tr '\n' ' ' | cut -c1-160)
              if [[ -n "$txt" ]]; then printf '%s* %s%s\n\n' "$D" "$txt" "$N"; fi
            fi ;;
          todo_list)
            txt=$(jq -r '[.item.items[]? | select(.completed == false)][0].text // empty' <<<"$line" 2>/dev/null)
            if [[ -n "$txt" ]]; then printf '%s> %s%s\n\n' "$D" "$txt" "$N"; fi ;;
        esac ;;
      turn.completed)
        txt=$(jq -r '"\(.usage.input_tokens // 0) in / \(.usage.output_tokens // 0) out"' <<<"$line" 2>/dev/null)
        printf '%sdone: %s%s\n\n' "$G" "$txt" "$N" ;;
      error)
        txt=$(jq -r '.message // "unknown error"' <<<"$line" 2>/dev/null)
        printf '%sERROR %s%s\n\n' "$R" "$txt" "$N" ;;
    esac
  done
  if [[ -n "$report" ]]; then printf '%sreport: %s%s\n' "$D" "$report" "$N"; fi
  return 0
}

run_codex() {
  # default per DECISIONS.md 2026-07-13 yolo ruling: codex runs unsandboxed
  local name="" model="" out="" resume="" prompt_file="" effort="" vis="" sandbox_mode="danger-full-access" workdir="" pane="" pid=""
  local tmux_target="" tmux_window="" right_pane="" candidate="" at_right=""
  local output_schema=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --model) model="$2"; shift 2 ;;
      --out) out="$2"; shift 2 ;;
      --resume) resume="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --effort) effort="$2"; shift 2 ;;
      --visibility) vis="$2"; shift 2 ;;
      --sandbox) sandbox_mode="$2"; shift 2 ;;
      --workdir) workdir="$2"; shift 2 ;;
      --output-schema) output_schema="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  [[ -n "$name" && -n "$model" && -n "$out" && -n "$prompt_file" ]] || usage
  case "$sandbox_mode" in read-only|workspace-write|danger-full-access) ;; *) usage ;; esac
  case "$effort" in ""|minimal|low|medium|high|xhigh) ;; *) usage ;; esac
  [[ -z "$output_schema" || -f "$output_schema" ]] || die "no output schema: $output_schema"
  [[ -f "$prompt_file" ]] || die "no prompt file: $prompt_file"
  [[ -z "$workdir" || -d "$workdir" ]] || die "no workdir: $workdir"
  # runner cd's to workdir, so relative --out/--prompt-file would resolve there
  [[ -z "$workdir" || ( "$out" == /* && "$prompt_file" == /* && ( -z "$output_schema" || "$output_schema" == /* ) ) ]] || die "absolute --out/--prompt-file required with --workdir"
  case "$out$prompt_file$workdir$output_schema" in *" "*) die "paths must not contain spaces" ;; esac
  if [[ -z "$vis" ]]; then vis="$(detect)"; fi
  if [[ "$vis" == "unset" ]]; then vis=background; fi

  local log="${out%.md}.log" sentinel="$out.done" runner="${out%.md}.run.sh" job="${out%.md}.job" color
  color="$(agent_color "$name")"
  rm -f "$out" "$sentinel" "$job"
  # web_search is off by default; -c form works on fresh AND resume (live-verified 0.144.1)
  local search="-c tools.web_search=true"
  local effort_flag=""
  [[ -n "$effort" ]] && effort_flag="-c model_reasoning_effort=$effort"
  local codex_cmd="codex exec -m $model $search $effort_flag" sandbox="-s $sandbox_mode"
  # resume subcommand rejects -s; set the sandbox via config instead
  if [[ -n "$resume" ]]; then codex_cmd="codex exec resume $resume -m $model $search $effort_flag"; sandbox="-c 'sandbox_mode=\"$sandbox_mode\"'"; fi
  local schema_flag=""
  [[ -n "$output_schema" ]] && schema_flag="--output-schema \"$output_schema\""
  local schema_check=""
  [[ -n "$output_schema" ]] && schema_check="if [[ \"\$rc\" == 0 ]] && ! jq -e . $out >/dev/null 2>&1; then echo \"FAIL: report not valid JSON: $out\" >> $log; rc=98; fi"
  local cd_line="" workdir_field=""
  [[ -n "$workdir" ]] && cd_line="cd $workdir || { echo 1 > $sentinel; exit 1; }"
  [[ -n "$workdir" ]] && workdir_field=" workdir=$workdir"
  cat > "$runner" <<EOF
#!/usr/bin/env bash
if [[ -t 1 ]]; then
  printf '\e[${color}mSpawning [$name sandbox=$sandbox_mode model=$model$workdir_field]\e[0m\n'
else
  printf 'Spawning [$name sandbox=$sandbox_mode model=$model$workdir_field]\n'
fi
$cd_line
printf '\e[2m--- prompt ---\n'
cat $prompt_file
printf -- '--------------\e[0m\n'
$codex_cmd $sandbox $schema_flag --json -o $out - < $prompt_file 2>&1 | $SCRIPT_DIR/codex-exec.sh render $log $out $color
rc="\${PIPESTATUS[0]}"
if [[ "\$rc" == 0 && ! -s $out ]]; then echo "FAIL: no report at $out" >> $log; rc=97; fi
$schema_check
echo "\$rc" > $sentinel
EOF
  chmod +x "$runner"

  case "$vis" in
    tmux)
      echo 'sleep 10' >> "$runner"   # pane lingers so the human can read the tail
      if [[ -n "${TMUX_PANE:-}" ]]; then
        tmux_target="$TMUX_PANE"
        tmux_window="$(tmux display-message -p -t "$tmux_target" '#{window_id}')"
        while IFS=' ' read -r candidate at_right; do
          if [[ "$candidate" != "$tmux_target" && "$at_right" == 1 ]]; then
            right_pane="$candidate"
          fi
        done < <(tmux list-panes -t "$tmux_window" -F '#{pane_id} #{pane_at_right}')
      fi
      if [[ -n "$right_pane" ]]; then
        pane="$(tmux split-window -d -v -t "$right_pane" -P -F '#{pane_id}' "$runner")"
      elif [[ -n "$tmux_target" ]]; then
        pane="$(tmux split-window -d -h -l 40% -t "$tmux_target" -P -F '#{pane_id}' "$runner")"
      else
        pane="$(tmux split-window -d -h -l 40% -P -F '#{pane_id}' "$runner")"
      fi
      tmux select-pane -t "$pane" -T "$name" || true ;;
    iterm)
      osascript \
        -e 'tell application "iTerm2"' \
        -e 'tell current session of current window' \
        -e "set newSession to split vertically with default profile command \"$runner\"" \
        -e 'end tell' \
        -e "set name of newSession to \"$name\"" \
        -e 'end tell' >/dev/null ;;
    window)
      osascript -e "tell application \"Terminal\" to do script \"$runner\"" >/dev/null ;;
    background)
      nohup "$runner" >/dev/null 2>&1 & pid=$! ;;
    *) die "unknown visibility: $vis" ;;
  esac
  jq -n --arg name "$name" --arg model "$model" --arg mode "$vis" \
    --arg out "$out" --arg log "$log" --arg sentinel "$sentinel" \
    --arg workdir "$workdir" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg pid "${pid:-}" --arg pane "${pane:-}" \
    '{name:$name, model:$model, mode:$mode, out:$out, log:$log,
      sentinel:$sentinel, created:$created}
     + (if $workdir != "" then {workdir:$workdir} else {} end)
     + (if $pid != "" then {pid:($pid|tonumber)} else {} end)
     + (if $pane != "" then {pane:$pane} else {} end)' > "$job"
  printf 'spawn=%s sandbox=%s color=%s\nreport=%s\nlog=%s\nsentinel=%s\nmode=%s\njob=%s\n' \
    "$name" "$sandbox_mode" "$color" "$out" "$log" "$sentinel" "$vis" "$job"
}

kill_run() {
  local out="${1:?}" job sentinel
  job="${out%.md}.job"
  sentinel="$out.done"
  [[ -f "$job" ]] || die "no job record: $job"
  if [[ -f "$sentinel" ]]; then
    echo "already done ($(cat "$sentinel"))"
    return 0
  fi
  local mode pid pane
  mode="$(jq -r .mode "$job")"
  pid="$(jq -r '.pid // empty' "$job")"
  pane="$(jq -r '.pane // empty' "$job")"
  case "$mode" in
    background)
      [[ -n "$pid" ]] || die "no pid in $job"
      # TERM runner children; the runner must survive to write PIPESTATUS.
      pkill -TERM -P "$pid" 2>/dev/null || true
      local i
      for ((i = 0; i < 20; i++)); do
        [[ -f "$sentinel" ]] && break
        sleep 0.5
      done
      if [[ ! -f "$sentinel" ]]; then
        pkill -KILL -P "$pid" 2>/dev/null || true
        kill -KILL "$pid" 2>/dev/null || true
      fi
      echo "killed pid=$pid" ;;
    tmux)
      [[ -n "$pane" ]] || die "no pane in $job"
      tmux kill-pane -t "$pane" 2>/dev/null || true
      echo "killed pane=$pane (no sentinel — pane died with the runner)" ;;
    *) die "kill unsupported for mode=$mode — close it by hand" ;;
  esac
}

status_run() {
  local out="${1:?}" job sentinel
  job="${out%.md}.job"
  sentinel="$out.done"
  if [[ -f "$sentinel" ]]; then
    echo "done $(cat "$sentinel")"
    return 0
  fi
  [[ -f "$job" ]] || die "no run for $out"
  local mode pid pane log age="?"
  mode="$(jq -r .mode "$job")"
  pid="$(jq -r '.pid // empty' "$job")"
  pane="$(jq -r '.pane // empty' "$job")"
  log="$(jq -r .log "$job")"
  if [[ -f "$log" ]]; then
    age="$(( $(date +%s) - $(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log") ))"
  fi
  case "$mode" in
    background)
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        echo "running pid=$pid log_age=${age}s"
      else
        echo dead
      fi ;;
    tmux)
      if [[ -n "$pane" ]] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane"; then
        echo "running pane=$pane log_age=${age}s"
      else
        echo dead
      fi ;;
    *) echo "running mode=$mode (no handle)" ;;
  esac
}

wait_run() {
  local out="${1:?}"
  shift
  local timeout=540
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --timeout) timeout="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  local sentinel="$out.done" deadline=$(( $(date +%s) + timeout )) s
  while true; do
    if [[ -f "$sentinel" ]]; then
      echo "done $(cat "$sentinel")"
      return 0
    fi
    s="$(status_run "$out")"
    if [[ "$s" == dead ]]; then
      echo dead
      return 3
    fi
    if (( $(date +%s) >= deadline )); then
      echo timeout
      return 124
    fi
    sleep 5
  done
}

case "${1:-}" in
  preflight) preflight ;;
  detect) detect ;;
  set-visibility) shift; set_visibility "$@" ;;
  session-id) shift; session_id "$@" ;;
  audit) shift; audit "$@" ;;
  run) shift; run_codex "$@" ;;
  kill) shift; kill_run "$@" ;;
  status) shift; status_run "$@" ;;
  wait) shift; wait_run "$@" ;;
  render) shift; render_stream "$@" ;;
  *) usage ;;
esac
