#!/usr/bin/env swift
import AppKit
import ApplicationServices

print("=== SimulTrans AX Diagnostics ===\n")

// 1. Check accessibility permission
let trusted = AXIsProcessTrusted()
print("1. Accessibility trusted: \(trusted)")
if !trusted {
    print("   -> Need to grant accessibility permission to Terminal/iTerm")
    print("   -> System Settings → Privacy & Security → Accessibility")
}

// 2. Find Live Captions process
print("\n2. Searching for Live Captions process...")

let allApps = NSWorkspace.shared.runningApplications
let candidates = allApps.filter {
    let bid = $0.bundleIdentifier ?? ""
    let name = $0.localizedName ?? ""
    return bid.contains("LiveTranscription") ||
           bid.contains("LiveCaption") ||
           bid.contains("caption") ||
           name.contains("Live Captions") ||
           name.contains("实时字幕")
}

if candidates.isEmpty {
    print("   -> NOT FOUND! Is Live Captions enabled?")
    print("   -> Go to System Settings → Accessibility → Live Captions")
    print("\n   All accessibility-related processes:")
    for app in allApps where (app.bundleIdentifier ?? "").contains("accessibility") {
        print("   - [\(app.processIdentifier)] \(app.bundleIdentifier ?? "?") (\(app.localizedName ?? "?"))")
    }
} else {
    for app in candidates {
        print("   -> Found: pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil")")

        // 3. Try to read AX tree
        print("\n3. Reading AX tree for pid \(app.processIdentifier)...")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get role
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleRef)
        print("   App role: \(roleRef as? String ?? "nil") (result: \(roleResult.rawValue))")

        // Get windows
        var windowsRef: CFTypeRef?
        let winResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        print("   Windows result: \(winResult.rawValue) (0=success, -25204=notAllowed, -25202=noValue)")

        if winResult == .success, let windows = windowsRef as? [AXUIElement] {
            print("   Window count: \(windows.count)")
            for (i, window) in windows.enumerated() {
                print("\n   --- Window \(i) ---")
                dumpElement(window, depth: 1, maxDepth: 8)
            }
        } else {
            print("   -> Cannot read windows! Error code: \(winResult.rawValue)")
            if winResult.rawValue == -25204 {
                print("   -> This means PERMISSION DENIED")
                print("   -> Add Terminal to Accessibility in System Settings")
            }

            // Try focused element as fallback
            var focusedRef: CFTypeRef?
            let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            print("   Focused element result: \(focusResult.rawValue)")
        }
    }
}

print("\n=== Done ===")

func dumpElement(_ element: AXUIElement, depth: Int, maxDepth: Int) {
    guard depth <= maxDepth else { return }
    let indent = String(repeating: "  ", count: depth)

    var roleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
    let role = (roleRef as? String) ?? "?"

    var valueRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
    let value = valueRef as? String

    var titleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
    let title = titleRef as? String

    var descRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
    let desc = descRef as? String

    var subRoleRef: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subRoleRef)
    let subRole = subRoleRef as? String

    var line = "\(indent)[\(role)]"
    if let subRole { line += "(\(subRole))" }
    if let title, !title.isEmpty { line += " title=\"\(title.prefix(60))\"" }
    if let value, !value.isEmpty { line += " value=\"\(value.prefix(100))\"" }
    if let desc, !desc.isEmpty { line += " desc=\"\(desc.prefix(60))\"" }
    print(line)

    var childrenRef: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
    if result == .success, let children = childrenRef as? [AXUIElement] {
        for child in children {
            dumpElement(child, depth: depth + 1, maxDepth: maxDepth)
        }
    }
}
