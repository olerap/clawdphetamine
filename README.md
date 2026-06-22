# clawdphetamine

A tiny native macOS background agent that runs only while a Claude Code session is
alive. Point an Amphetamine **Application** trigger at it and your Mac stays awake
during Claude Code — and only then. No Electron, no Node, no plugin; ~85 KB of Swift.

Amphetamine can only trigger on a running *app*, not on the `claude` CLI — so this is
that app: an invisible process that exists exactly as long as Claude Code runs.

## Install

```sh
brew tap olerap/clawdphetamine
brew install clawdphetamine
```

(Or from source: `./build.sh` — needs the Xcode Command Line Tools.)

## Setup

1. Add the hook to `~/.claude/settings.json` (Homebrew prints the absolute path in its
   caveats; a source build uses `~/clawdphetamine/claude-hook.sh`):

   ```json
   "hooks": {
     "SessionStart":     [ { "hooks": [ { "type": "command", "command": "clawdphetamine-hook" } ] } ],
     "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "clawdphetamine-hook" } ] } ]
   }
   ```

2. Amphetamine → Preferences → Triggers → add an **Application** trigger for
   `clawdphetamine` (bundle id `nl.olerap.clawdphetamine`).

## How it works

The hook writes a marker named after the `claude` PID and launches the agent. The agent
polls every 5 s; a marker is live while its PID is alive, and the agent quits once none
remain. Its exit is what releases the trigger — so cleanup is automatic on a clean exit,
a crash, or a terminal quit (no `SessionEnd` hook needed). Concurrent sessions are
ref-counted (one marker per PID).

## Uninstall

```sh
brew uninstall clawdphetamine && brew untap olerap/clawdphetamine
# then remove the "hooks" entries from ~/.claude/settings.json
```
