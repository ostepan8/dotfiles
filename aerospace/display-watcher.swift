// Tiny launchd-friendly daemon that runs `set-main-display.sh auto` whenever
// the macOS display configuration changes (plug, unplug, reorder, rotation,
// resolution change).
//
// Uses CGDisplayRegisterReconfigurationCallback. macOS fires the callback
// twice per display per change: once *before* with `beginConfigurationFlag`,
// once *after* with the actual change flags (Moved / SetMain / Add / Remove /
// SetMode / etc.). We skip the begin calls and act on the after ones, then
// debounce so a burst of "after" callbacks collapses into a single script
// run. A small delay gives macOS time to finish settling before the script
// asks displayplacer / aerospace for the new layout.
//
// Build:
//   swiftc -O display-watcher.swift -o display-watcher
//
// Run via the com.ostepan.display-watcher LaunchAgent (KeepAlive). It never
// exits on its own — the launchd job is the only thing that stops it.

import CoreGraphics
import Foundation

let script = ("~/.config/aerospace/set-main-display.sh" as NSString).expandingTildeInPath

// Debounce so a burst of callbacks (one per display) only runs the script once.
let queue = DispatchQueue(label: "display-watcher.debounce")
var pendingWorkItem: DispatchWorkItem?

func runScript() {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-lc", "\"\(script)\" auto"]
    task.standardOutput = FileHandle(forWritingAtPath: "/tmp/aerospace-display-watcher.out")
    task.standardError = FileHandle(forWritingAtPath: "/tmp/aerospace-display-watcher.err")
    do {
        try task.run()
    } catch {
        FileHandle.standardError.write(Data("display-watcher: failed to run script: \(error)\n".utf8))
    }
}

func schedule() {
    queue.async {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem { runScript() }
        pendingWorkItem = work
        // 1.2s — enough for macOS to finish reconfiguring displays, short enough
        // that a real user-visible delay isn't noticeable.
        queue.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}

let callback: CGDisplayReconfigurationCallBack = { _, flags, _ in
    // Skip the pre-change call (kCGDisplayBeginConfigurationFlag = 1). The
    // post-change call carries any of the other flags (Moved, SetMain, Add,
    // Remove, SetMode, etc.) without the begin bit.
    let beginFlag = CGDisplayChangeSummaryFlags.beginConfigurationFlag.rawValue
    if (flags.rawValue & beginFlag) == 0 {
        schedule()
    }
}

CGDisplayRegisterReconfigurationCallback(callback, nil)

// Also run once at launch so a freshly-loaded LaunchAgent picks up the
// current monitor layout (e.g. machine booted with one external attached).
schedule()

RunLoop.current.run()
