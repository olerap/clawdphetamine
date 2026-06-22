import Cocoa
import Darwin

// clawdphetamine — a minimal macOS background agent that exists exactly while at least
// one Claude Code session process is alive.
//
// Why: Amphetamine can only trigger on a running *application*, not on the `claude`
// CLI. This agent is that application. Pair it with an Amphetamine "Application"
// trigger so your Mac stays awake only while Claude Code is running.
//
// Mechanism (see README.md):
//   • Claude Code hooks drop a marker file named after the `claude` process PID
//     into ~/.local/state/clawdphetamine/sessions/ at session start.
//   • This agent polls that directory every `pollInterval` seconds. A marker is
//     "live" while its PID is alive (kill(pid,0)). Dead-PID markers are removed.
//   • When no live markers remain, the agent quits. Its own process exit is what
//     releases the Amphetamine trigger — so cleanup is automatic on a clean exit,
//     a crash, OR a terminal quit (anything that kills the claude process).

let sessionsDir = NSString(string: "~/.local/state/clawdphetamine/sessions").expandingTildeInPath
let pollInterval: TimeInterval = 5.0
let maxAgeSeconds: TimeInterval = 24 * 60 * 60   // backstop against PID reuse

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
            var alive = pidIsAlive(pid)
            if alive,
               let attrs = try? fm.attributesOfItem(atPath: path),
               let mtime = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(mtime) > maxAgeSeconds {
                alive = false            // stale: assume PID was reused
            }
            if alive { live += 1 } else { try? fm.removeItem(atPath: path) }
        }
        if live == 0 { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)      // background agent — no Dock icon, no menu-bar item
let delegate = AppDelegate()
app.delegate = delegate
app.run()
