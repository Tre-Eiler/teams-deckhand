// Phase 0 feasibility spike: can we find and press Teams' mute/camera
// buttons via the macOS Accessibility (AX) API?
//
// Usage:
//   swiftc spike.swift -o spike && ./spike dump          (discover candidate buttons)
//   ./spike press <domId-or-title-substring>              (press one and show before/after)
//
// Run `dump` WHILE you are in an active Teams call/meeting — the
// mute/camera toolbar only exists inside a meeting window.

import ApplicationServices
import AppKit
import Foundation

// MARK: - Accessibility permission

func ensureAccessibilityTrusted() {
    let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let trusted = AXIsProcessTrustedWithOptions(opts)
    if !trusted {
        print("""
        Not yet trusted for Accessibility.
        A system prompt should have appeared — grant access to this binary in
        System Settings > Privacy & Security > Accessibility, then re-run.
        (If it's already in that list, remove it and re-add it — macOS sometimes
        needs a fresh toggle after a rebuild.)
        """)
        exit(1)
    }
}

// MARK: - AX helpers

func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return err == .success ? value : nil
}

func stringAttr(_ element: AXUIElement, _ name: String) -> String? {
    attr(element, name) as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

struct Candidate {
    let path: String
    let element: AXUIElement
    let role: String
    let title: String
    let domId: String
    let description: String
    let value: String
}

func describe(_ element: AXUIElement, path: String) -> Candidate {
    let role = stringAttr(element, kAXRoleAttribute) ?? ""
    let title = stringAttr(element, kAXTitleAttribute) ?? ""
    let domId = stringAttr(element, "AXDOMIdentifier") ?? ""
    let desc = stringAttr(element, kAXDescriptionAttribute) ?? ""
    let value = (attr(element, kAXValueAttribute) as? String) ?? ""
    return Candidate(path: path, element: element, role: role, title: title, domId: domId, description: desc, value: value)
}

let keywords = ["mute", "unmute", "mic", "microphone", "camera", "video", "cam", "hand", "react", "roster", "people"]

func matchesKeyword(_ c: Candidate) -> Bool {
    let hay = (c.title + " " + c.domId + " " + c.description).lowercased()
    return keywords.contains { hay.contains($0) }
}

var visited = 0
let maxVisited = 40000
let maxDepth = 45

func walk(_ element: AXUIElement, path: String, depth: Int, into results: inout [Candidate]) {
    visited += 1
    if visited > maxVisited || depth > maxDepth { return }
    let c = describe(element, path: path)
    let role = c.role
    if (role == kAXButtonRole || role == kAXCheckBoxRole || role == "AXToggle") && matchesKeyword(c) {
        results.append(c)
    }
    for (i, child) in children(element).enumerated() {
        walk(child, path: "\(path)/\(i)", depth: depth + 1, into: &results)
    }
}

// MARK: - Finding Teams

let teamsBundleIds = ["com.microsoft.teams2", "com.microsoft.teams"]

func findTeams() -> NSRunningApplication? {
    let apps = NSWorkspace.shared.runningApplications
    if let byId = apps.first(where: { teamsBundleIds.contains($0.bundleIdentifier ?? "") }) {
        return byId
    }
    return apps.first(where: { ($0.localizedName ?? "").lowercased().contains("teams") })
}

// MARK: - Commands

func forceAccessibilityTree(_ app: AXUIElement) {
    // Chromium/Electron only builds the full AX tree when it thinks assistive
    // tech is active. Poking this attribute (used by Chrome/Electron/CEF)
    // forces it on. Errors are ignored — not every app supports it.
    _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
}

func dump() {
    guard let teams = findTeams() else {
        print("Teams not found among running applications. Is it running?")
        exit(1)
    }
    print("Found Teams: \(teams.localizedName ?? "?") pid=\(teams.processIdentifier) bundleId=\(teams.bundleIdentifier ?? "?")")

    let app = AXUIElementCreateApplication(teams.processIdentifier)
    forceAccessibilityTree(app)
    Thread.sleep(forTimeInterval: 0.5)
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    print("Windows: \(windows.count)")

    var results: [Candidate] = []
    for (wi, window) in windows.enumerated() {
        let title = stringAttr(window, kAXTitleAttribute) ?? "(untitled)"
        print("  [\(wi)] \"\(title)\"")
        walk(window, path: "w\(wi)", depth: 0, into: &results)
    }

    print("\nVisited \(visited) elements. Candidates matching mute/camera keywords: \(results.count)\n")
    for c in results {
        print("""
        path=\(c.path)
          role=\(c.role)
          title=\"\(c.title)\"
          domId=\"\(c.domId)\"
          description=\"\(c.description)\"
          value=\"\(c.value)\"
        """)
    }
    if results.isEmpty {
        print("No matches. Possible causes: not currently in a meeting, or Teams uses different labels/roles than expected — widen `keywords` above and re-run.")
    }
}

func press(_ needle: String) {
    guard let teams = findTeams() else {
        print("Teams not found among running applications. Is it running?")
        exit(1)
    }
    let app = AXUIElementCreateApplication(teams.processIdentifier)
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []

    var results: [Candidate] = []
    for window in windows {
        walk(window, path: "w", depth: 0, into: &results)
    }

    guard let target = results.first(where: {
        $0.domId.lowercased().contains(needle.lowercased()) || $0.title.lowercased().contains(needle.lowercased())
    }) else {
        print("No candidate matched \"\(needle)\". Run `dump` first to see available candidates.")
        exit(1)
    }

    print("Before: title=\"\(target.title)\" domId=\"\(target.domId)\" description=\"\(target.description)\" value=\"\(target.value)\"")
    let err = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
    if err != .success {
        print("AXPress failed with error \(err.rawValue)")
        exit(1)
    }
    Thread.sleep(forTimeInterval: 0.3)
    let after = describe(target.element, path: target.path)
    print("After:  title=\"\(after.title)\" domId=\"\(after.domId)\" description=\"\(after.description)\" value=\"\(after.value)\"")
}

func rawDump(windowTitlePrefix: String, maxRawDepth: Int) {
    guard let teams = findTeams() else {
        print("Teams not found among running applications. Is it running?")
        exit(1)
    }
    let app = AXUIElementCreateApplication(teams.processIdentifier)
    forceAccessibilityTree(app)
    Thread.sleep(forTimeInterval: 0.5)
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    let titles = windows.map { stringAttr($0, kAXTitleAttribute) ?? "(untitled)" }
    guard let idx = titles.firstIndex(where: { $0.hasPrefix(windowTitlePrefix) }) else {
        print("No window with title prefix \"\(windowTitlePrefix)\". Windows: \(titles)")
        exit(1)
    }
    let windowIndex = idx
    var count = 0
    func rec(_ el: AXUIElement, depth: Int) {
        count += 1
        if count > maxVisited || depth > maxRawDepth { return }
        let c = describe(el, path: "")
        let indent = String(repeating: "  ", count: depth)
        print("\(indent)role=\(c.role) title=\"\(c.title)\" domId=\"\(c.domId)\" desc=\"\(c.description)\"")
        for child in children(el) {
            rec(child, depth: depth + 1)
        }
    }
    rec(windows[windowIndex], depth: 0)
    print("\nTotal elements: \(count)")
}

func inspect(_ needle: String) {
    guard let teams = findTeams() else {
        print("Teams not found among running applications. Is it running?")
        exit(1)
    }
    let app = AXUIElementCreateApplication(teams.processIdentifier)
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []

    var results: [Candidate] = []
    for window in windows {
        walk(window, path: "w", depth: 0, into: &results)
    }
    guard let target = results.first(where: {
        $0.domId.lowercased().contains(needle.lowercased()) || $0.title.lowercased().contains(needle.lowercased())
    }) else {
        print("No candidate matched \"\(needle)\".")
        exit(1)
    }

    var namesRef: CFArray?
    let err = AXUIElementCopyAttributeNames(target.element, &namesRef)
    guard err == .success, let names = namesRef as? [String] else {
        print("Failed to get attribute names: \(err.rawValue)")
        exit(1)
    }
    print("Attributes for \(target.domId):")
    for name in names {
        let value = attr(target.element, name)
        print("  \(name) = \(String(describing: value))")
    }
}

func siblings(_ needle: String) {
    guard let teams = findTeams() else {
        print("Teams not found among running applications. Is it running?")
        exit(1)
    }
    let app = AXUIElementCreateApplication(teams.processIdentifier)
    let windows = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []

    var results: [Candidate] = []
    for window in windows {
        walk(window, path: "w", depth: 0, into: &results)
    }
    guard let target = results.first(where: {
        $0.domId.lowercased().contains(needle.lowercased()) || $0.title.lowercased().contains(needle.lowercased())
    }) else {
        print("No candidate matched \"\(needle)\".")
        exit(1)
    }
    guard let parent = attr(target.element, kAXParentAttribute) else {
        print("No parent found")
        exit(1)
    }
    // swiftlint:disable:next force_cast
    let parentElement = parent as! AXUIElement
    let siblings = children(parentElement)
    print("Parent has \(siblings.count) children:")
    for (i, sib) in siblings.enumerated() {
        let c = describe(sib, path: "\(i)")
        print("  [\(i)] role=\(c.role) title=\"\(c.title)\" domId=\"\(c.domId)\" desc=\"\(c.description)\" value=\"\(c.value)\"")
    }
}

// MARK: - Main

ensureAccessibilityTrusted()

let args = CommandLine.arguments
if args.count >= 2 && args[1] == "press" {
    guard args.count >= 3 else {
        print("Usage: ./spike press <domId-or-title-substring>")
        exit(1)
    }
    press(args[2])
} else if args.count >= 2 && args[1] == "siblings" {
    guard args.count >= 3 else {
        print("Usage: ./spike siblings <domId-or-title-substring>")
        exit(1)
    }
    siblings(args[2])
} else if args.count >= 2 && args[1] == "inspect" {
    guard args.count >= 3 else {
        print("Usage: ./spike inspect <domId-or-title-substring>")
        exit(1)
    }
    inspect(args[2])
} else if args.count >= 2 && args[1] == "raw" {
    let titlePrefix = args.count >= 3 ? args[2] : "Meeting"
    let depth = args.count >= 4 ? Int(args[3]) ?? 12 : 12
    rawDump(windowTitlePrefix: titlePrefix, maxRawDepth: depth)
} else {
    dump()
}
