import Cocoa
import Darwin

// clawdphetamine — a minimal macOS background agent that runs only while Claude Code
// is actively working, so an Amphetamine "Application" trigger keeps the Mac awake
// during a turn (plus a short grace after) but not while a session sits idle.
//
// Why: Amphetamine can only trigger on a running *application*, not on the `claude`
// CLI — so this agent is that application.
//
// Mechanism (see README.md): Claude Code hooks write a marker file per session, named
// after the `claude` PID, holding the state "busy" or "idle":
//     UserPromptSubmit -> "busy" (turn started)     Stop -> "idle" (turn ended)
// Each poll, a marker counts as live while the PID is alive AND (state is "busy", OR it
// went "idle" less than `graceSeconds` ago). When no live markers remain the agent quits
// — its exit releases the trigger. A dead PID is always pruned (crash net).

let sessionsDir = NSString(string: "~/.local/state/clawdphetamine/sessions").expandingTildeInPath
let pollInterval: TimeInterval = 5.0
let graceSeconds: TimeInterval = 600             // stay awake this long after a turn ends (idle)
let maxAgeSeconds: TimeInterval = 24 * 60 * 60   // backstop: drop a "busy" marker stuck this long

func pidIsAlive(_ pid: pid_t) -> Bool {
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM            // process exists but is owned by another user
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // Single-instance guard. `open(1)` already dedupes launches via LaunchServices;
        // this also covers a direct double-exec.
        let me = NSRunningApplication.current
        if let bid = me.bundleIdentifier {
            let hasDuplicate = NSRunningApplication
                .runningApplications(withBundleIdentifier: bid)
                .contains { $0.processIdentifier != me.processIdentifier }
            if hasDuplicate { NSApp.terminate(nil); return }
        }

        // No UI by design: this app exists only so Amphetamine's Application trigger
        // has a process to watch (matched by bundle id). The menu-bar icon was removed
        // — it duplicated Amphetamine's own status item.
        tick()
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        let names = (try? fm.contentsOfDirectory(atPath: sessionsDir)) ?? []
        var live = 0
        for name in names {
            let path = (sessionsDir as NSString).appendingPathComponent(name)
            guard let pid = pid_t(name) else { try? fm.removeItem(atPath: path); continue }
            if !pidIsAlive(pid) { try? fm.removeItem(atPath: path); continue }   // crash net

            let state = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let attrs = try? fm.attributesOfItem(atPath: path)
            let mtime = attrs?[.modificationDate] as? Date
            let age = mtime.map { Date().timeIntervalSince($0) } ?? 0

            // "idle" markers expire after the grace window; "busy" (or legacy/unknown)
            // markers stay live until a long backstop — covers arbitrarily long turns.
            let limit = (state == "idle") ? graceSeconds : maxAgeSeconds
            if age < limit { live += 1 } else { try? fm.removeItem(atPath: path) }
        }
        if live == 0 { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // background agent — no Dock icon, no menu-bar item
let delegate = AppDelegate()
app.delegate = delegate
app.run()
