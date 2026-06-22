#!/bin/bash
# clawdphetamine hook — record this Claude Code session's busy/idle state for the agent.
# Wired into ~/.claude/settings.json:
#   UserPromptSubmit -> "busy" (a turn started)     Stop -> "idle" (the turn ended)
# Cheap (no node, no JSON parsing) and idempotent. The marker is keyed on the `claude`
# PID, so the agent also cleans up automatically if the process dies (crash/quit).

set -u

# Find the nearest ancestor process named "claude" (the Claude Code session).
# Hooks run under one or more intermediate shells, so $PPID is not reliable on its
# own — walk up the parent chain until we hit "claude".
find_claude_pid() {
    local pid=$PPID comm
    local i=0
    while [ "${pid:-0}" -gt 1 ] && [ "$i" -lt 12 ]; do
        comm=$(ps -o comm= -p "$pid" 2>/dev/null)
        case "$comm" in
            claude|*/claude) printf '%s' "$pid"; return 0 ;;
        esac
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        i=$((i + 1))
    done
    printf '%s' "$PPID"   # fallback: best effort
}

STATE="${1:-busy}"                                 # "busy" (turn active) or "idle" (turn ended)
CPID=$(find_claude_pid)
DIR="$HOME/.local/state/clawdphetamine/sessions"
# App location: env override (set by the Homebrew formula) else the default install path.
APP="${CLAWDPHETAMINE_APP:-$HOME/Applications/clawdphetamine.app}"

mkdir -p "$DIR"
printf '%s' "$STATE" > "$DIR/$CPID"               # marker: name=PID, contents=state, mtime=now
[ "$STATE" = busy ] && open -g "$APP" >/dev/null 2>&1 || true   # launch agent when work starts

exit 0
