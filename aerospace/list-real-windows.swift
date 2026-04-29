// Print one TSV line per PID-with-windows: PID<TAB>OWNER<TAB>AX_WINDOW_COUNT
//
// Uses the Accessibility API (the same source AeroSpace uses) to ask each
// running app how many windows it actually has right now. Compare against
// AeroSpace's tracked count per PID; the difference is the phantom count.
//
// Compile: swiftc -O list-real-windows.swift -o list-real-windows
// Run:     ./list-real-windows

import Foundation
import AppKit
import ApplicationServices

// Iterate over running apps and count their AXWindows.
let workspace = NSWorkspace.shared
for app in workspace.runningApplications {
    // Skip processes with no UI (background services).
    if app.activationPolicy != .regular { continue }
    let pid = app.processIdentifier
    let name = app.localizedName ?? "?"

    let appElement = AXUIElementCreateApplication(pid)
    var rawValue: AnyObject?
    let err = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawValue)
    if err != .success {
        // App didn't respond / not accessibility-enabled. Don't print anything;
        // the watchdog interprets "no entry" as "we don't know" and leaves the
        // PID's AeroSpace windows alone.
        continue
    }
    guard let windows = rawValue as? [AXUIElement] else { continue }

    let safeName = name
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    print("\(pid)\t\(safeName)\t\(windows.count)")
}
