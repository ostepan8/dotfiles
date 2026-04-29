// Print one TSV line per AX window: PID<TAB>APP<TAB>TITLE<TAB>MINIMIZED<TAB>HIDDEN<TAB>WIDTH<TAB>HEIGHT
//
// Cleanup script treats a window as "visible" only when minimized=0,
// hidden=0, and width/height are non-trivial. AeroSpace counts > visible
// counts → phantoms (e.g. minimized windows still in AeroSpace's tiling
// tree, taking up space invisibly on the screen).
//
// Compile: swiftc -O list-real-windows.swift -o list-real-windows
// Run:     ./list-real-windows

import Foundation
import AppKit
import ApplicationServices

func boolAttr(_ el: AXUIElement, _ key: String) -> Bool {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, key as CFString, &raw) == .success,
          let v = raw as? Bool else { return false }
    return v
}

func stringAttr(_ el: AXUIElement, _ key: String) -> String {
    var raw: AnyObject?
    guard AXUIElementCopyAttributeValue(el, key as CFString, &raw) == .success,
          let v = raw as? String else { return "" }
    return v
}

func sizeAttr(_ el: AXUIElement) -> CGSize {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &raw) == .success,
          let v = raw, CFGetTypeID(v) == AXValueGetTypeID() else {
        return .zero
    }
    var size = CGSize.zero
    AXValueGetValue(v as! AXValue, .cgSize, &size)
    return size
}

let workspace = NSWorkspace.shared
for app in workspace.runningApplications {
    if app.activationPolicy != .regular { continue }
    let pid = app.processIdentifier
    let name = (app.localizedName ?? "?")
        .replacingOccurrences(of: "\t", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
    let appHidden = app.isHidden ? 1 : 0

    let appElement = AXUIElementCreateApplication(pid)
    var rawValue: AnyObject?
    if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &rawValue) != .success { continue }
    guard let windows = rawValue as? [AXUIElement] else { continue }

    for w in windows {
        let title = stringAttr(w, kAXTitleAttribute as String)
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let minimized = boolAttr(w, kAXMinimizedAttribute as String) ? 1 : 0
        let size = sizeAttr(w)
        print("\(pid)\t\(name)\t\(title)\t\(minimized)\t\(appHidden)\t\(Int(size.width))\t\(Int(size.height))")
    }
}
