#!/bin/bash
# clawdphetamine hook — register this Claude Code session and make sure the background
# agent is running. Wired into ~/.claude/settings.json on SessionStart and
# UserPromptSubmit. Designed to be cheap (no node, no JSON parsing) and idempotent.
#
# It keys the session marker on the PID of the `claude` process. Because the agent
# watches that PID for liveness, cleanup happens automatically when the process
# dies for ANY reason (clean exit, crash, or terminal quit) — no SessionEnd needed.

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

CPID=$(find_claude_pid)
DIR="$HOME/.local/state/clawdphetamine/sessions"
# App location: env override (set by the Homebrew formula) else the default install path.
APP="${CLAWDPHETAMINE_APP:-$HOME/Applications/clawdphetamine.app}"

mkdir -p "$DIR"
: > "$DIR/$CPID"                                   # marker (name = PID, mtime = last seen)
open -g "$APP" >/dev/null 2>&1 || true            # launch agent if not already running

exit 0
