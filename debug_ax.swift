#!/usr/bin/env swift
import AppKit
import ApplicationServices

print("=== SimulTrans アクセシビリティ診断 ===\n")

// 1. アクセシビリティ権限を確認
let trusted = AXIsProcessTrusted()
print("1. アクセシビリティ権限: \(trusted)")
if !trusted {
    print("   -> Terminal または iTerm にアクセシビリティ権限を付与してください")
    print("   -> システム設定 → プライバシーとセキュリティ → アクセシビリティ")
}

// 2. ライブキャプションのプロセスを探す
print("\n2. ライブキャプションのプロセスを検索しています...")

let allApps = NSWorkspace.shared.runningApplications
let candidates = allApps.filter {
    let bid = $0.bundleIdentifier ?? ""
    let name = $0.localizedName ?? ""
    return bid.contains("LiveTranscription") ||
           bid.contains("LiveCaption") ||
           bid.contains("caption") ||
           name.contains("Live Captions") ||
           name.contains("ライブキャプション") ||
           name.contains("实时字幕")
}

if candidates.isEmpty {
    print("   -> 見つかりません。ライブキャプションが有効か確認してください")
    print("   -> システム設定 → アクセシビリティ → ライブキャプション")
    print("\n   アクセシビリティ関連のプロセス一覧:")
    for app in allApps where (app.bundleIdentifier ?? "").contains("accessibility") {
        print("   - [\(app.processIdentifier)] \(app.bundleIdentifier ?? "?") (\(app.localizedName ?? "?"))")
    }
} else {
    for app in candidates {
        print("   -> 検出: pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil")")

        // 3. AX ツリーを読む
        print("\n3. pid \(app.processIdentifier) の AX ツリーを読み取っています...")
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Role を取得
        var roleRef: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &roleRef)
        print("   App role: \(roleRef as? String ?? "nil") (result: \(roleResult.rawValue))")

        // Window を取得
        var windowsRef: CFTypeRef?
        let winResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        print("   Windows result: \(winResult.rawValue) (0=success, -25204=権限不足, -25202=値なし)")

        if winResult == .success, let windows = windowsRef as? [AXUIElement] {
            print("   Window 数: \(windows.count)")
            for (i, window) in windows.enumerated() {
                print("\n   --- Window \(i) ---")
                dumpElement(window, depth: 1, maxDepth: 8)
            }
        } else {
            print("   -> Window を読み取れません。Error code: \(winResult.rawValue)")
            if winResult.rawValue == -25204 {
                print("   -> アクセシビリティ権限が拒否されています")
                print("   -> システム設定で Terminal にアクセシビリティ権限を追加してください")
            }

            // Fallback として focused element を試す
            var focusedRef: CFTypeRef?
            let focusResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedRef)
            print("   Focused element result: \(focusResult.rawValue)")
        }
    }
}

print("\n=== 完了 ===")

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
