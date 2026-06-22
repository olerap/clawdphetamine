# clawdphetamine

A tiny native macOS background agent that runs only while Claude Code is actively
working. Point an Amphetamine **Application** trigger at it and your Mac stays awake
during a turn (plus a short grace) — not while a session just sits open idle.
No Electron, no Node, no plugin; ~85 KB of Swift.

Amphetamine can only trigger on a running *app*, not on the `claude` CLI — so this is
that app: an invisible process that exists only while a turn is in flight.

## Install

```sh
brew tap olerap/clawdphetamine
brew install clawdphetamine
```

(Or from source: `./build.sh` — needs the Xcode Command Line Tools.)

## Setup

1. Add the hooks to `~/.claude/settings.json` (Homebrew prints the absolute path in its
   caveats; a source build uses `~/clawdphetamine/claude-hook.sh`):

   ```json
   "hooks": {
     "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "clawdphetamine-hook busy" } ] } ],
     "Stop":             [ { "hooks": [ { "type": "command", "command": "clawdphetamine-hook idle" } ] } ]
   }
   ```

2. Amphetamine → Preferences → Triggers → add an **Application** trigger for
   `clawdphetamine` (bundle id `nl.olerap.clawdphetamine`).

## How it works

The hooks write one marker per session (named after the `claude` PID) holding `busy` or
`idle`: `UserPromptSubmit` → busy, `Stop` → idle. The agent polls every 5 s and stays
alive while any marker is **busy**, or went **idle** less than ~10 min ago (a grace
window, so reading between turns doesn't drop it). When none qualify it quits, releasing
the trigger. A long turn never expires (busy isn't time-based); a dead `claude` PID is
always pruned (crash/quit safety); concurrent sessions are ref-counted.

Tune `graceSeconds` in `clawdphetamine.swift` (default 600).

## Uninstall

```sh
brew uninstall clawdphetamine && brew untap olerap/clawdphetamine
# then remove the "hooks" entries from ~/.claude/settings.json
```
