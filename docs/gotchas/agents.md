# Agents

## Teammate panes die silently after CLI auto-update prunes the session's binary
Symptom: Agent-tool teammates (pane runner) spawn "successfully", ListAgents shows them running for 20+ min, but nothing ever happens — no output, no notification (3x in one session: 2 spec-judges, 1 pr-reviewer).
Cause: a long-lived session spawns panes with its own pinned binary path (`~/.local/share/claude/versions/<v>`); the auto-updater deletes old versions, the pane exits 127 (`env: … No such file or directory`) and the death is never propagated.
Rule: a pane teammate silent for ~10 min → `tmux capture-pane -p -t <pane>` and look for "Pane is dead"; if the version dir is gone, stop the teammate and reroute the role to codex-exec.sh or an in-process bg Agent (they don't use the pane binary). Restarting the session also clears it.
