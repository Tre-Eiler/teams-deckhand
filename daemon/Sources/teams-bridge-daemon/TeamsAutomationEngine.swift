import ApplicationServices
import AppKit
import Foundation

/// Drives Microsoft Teams' own mute/camera/raise-hand toolbar buttons via the
/// macOS Accessibility API. This is the one fragile part of the system — see
/// spike/spike.swift for how these identifiers were discovered, and re-run
/// that spike (or hit /diagnostics) if Teams changes its UI and this stops
/// finding buttons.
final class TeamsAutomationEngine {
    private static let teamsBundleIds = ["com.microsoft.teams2", "com.microsoft.teams"]
    /// While no call is found, look again this often rather than on every
    /// poll tick: scanning every Teams window isn't free.
    private static let idleRescanInterval: TimeInterval = 1.5
    /// Even while the cached buttons still read fine, re-find them this often:
    /// Teams can redraw its toolbar and leave us holding a node that still
    /// answers (with an old label) but no longer reflects reality.
    private static let revalidateInterval: TimeInterval = 10

    private var cachedPid: pid_t?
    private var cachedApp: AXUIElement?
    private var forcedAXTree = false
    private var cachedMicElement: AXUIElement?
    private var cachedCameraElement: AXUIElement?
    private var cachedHandElement: AXUIElement?
    private var cachedHangUpElement: AXUIElement?
    private var lastScanAt: Date?
    private var lastScanInCall = false
    private var lastValidatedAt: Date?
    private var loggedState: String?

    /// Optimistic hand-raised flag — see `Status.handRaised` for why this
    /// isn't read back from Teams.
    private var handRaisedState = false

    // Serializes access to the cached AX refs above: the poll Timer (main
    // thread) and HTTP toggle handlers (Swifter's background thread) can
    // both call in concurrently.
    private let lock = NSLock()

    // MARK: - Health (cheap; safe to call every tick)

    var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }
    var isTeamsRunning: Bool { findRunningTeams() != nil }

    // MARK: - AX plumbing

    private func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return err == .success ? value : nil
    }

    private func stringAttr(_ element: AXUIElement, _ name: String) -> String? {
        attr(element, name) as? String
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    private func findRunningTeams() -> NSRunningApplication? {
        let apps = NSWorkspace.shared.runningApplications
        if let byId = apps.first(where: { Self.teamsBundleIds.contains($0.bundleIdentifier ?? "") }) {
            return byId
        }
        return apps.first(where: { ($0.localizedName ?? "").lowercased().contains("teams") })
    }

    /// Chromium/Electron only builds the full AX tree when it thinks assistive
    /// tech is active. This forces it on; errors are ignored (not every
    /// element supports it, but Teams does).
    private func forceAccessibilityTreeIfNeeded(_ app: AXUIElement) {
        guard !forcedAXTree else { return }
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        forcedAXTree = true
    }

    private func windows(of app: AXUIElement) -> [AXUIElement] {
        (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    private func title(of window: AXUIElement) -> String {
        stringAttr(window, kAXTitleAttribute) ?? ""
    }

    private struct Controls {
        var mic: AXUIElement?
        var camera: AXUIElement?
        var hand: AXUIElement?
        var hangUp: AXUIElement?

        var complete: Bool { mic != nil && camera != nil && hand != nil && hangUp != nil }
        /// Mic and camera are what make something "a call"; the hand button
        /// isn't present in every meeting type.
        var isCall: Bool { mic != nil && camera != nil }
    }

    /// Walks a window's AX tree for the toolbar buttons (matched by their DOM
    /// ids). `exhaustive` keeps going past the first hit and returns how many
    /// nodes there are — for diagnostics.
    private func findControls(in window: AXUIElement, exhaustive: Bool = false) -> (controls: Controls, nodes: Int) {
        var found = Controls()
        var visited = 0
        func rec(_ el: AXUIElement, depth: Int) {
            if (!exhaustive && found.complete) || visited > 40000 || depth > 45 { return }
            visited += 1
            if let domId = stringAttr(el, "AXDOMIdentifier") {
                if domId == "microphone-button" { found.mic = el }
                else if domId == "video-button" { found.camera = el }
                else if domId == "raisehands-button" { found.hand = el }
                else if domId == "hangup-button" { found.hangUp = el }
            }
            for child in children(el) {
                if !exhaustive && found.complete { return }
                rec(child, depth: depth + 1)
            }
        }
        rec(window, depth: 0)
        return (found, visited)
    }

    /// Finds the window holding a call's controls. Any Teams window can: a
    /// meeting's title is its own name (not necessarily "Meeting…"), and
    /// depending on settings a call may live in the main window. Windows
    /// titled "Meeting…" — where calls were first seen — go first.
    private func scanForCallControls(in app: AXUIElement) -> Controls? {
        let all = windows(of: app)
        let meetingTitled = all.filter { title(of: $0).hasPrefix("Meeting") }
        let others = all.filter { !title(of: $0).hasPrefix("Meeting") }
        for window in meetingTitled + others {
            let controls = findControls(in: window).controls
            if controls.isCall { return controls }
        }
        return nil
    }

    // Teams reports the *action* the button performs, not the current state,
    // so the meaning is inverted: "Mute mic" means the mic is currently live.
    // Matched loosely (case-insensitive, any wording around the key words) so
    // small label differences between Teams versions don't break it. Labels
    // in other languages return nil — /diagnostics shows the raw label.
    private func micEnabled(fromDescription d: String) -> Bool? {
        let text = d.lowercased()
        if text.contains("unmute") { return false }
        if text.contains("mute") { return true }
        return nil
    }

    private func cameraEnabled(fromDescription d: String) -> Bool? {
        let words = Set(d.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        if words.contains("off") || words.contains("stop") { return true }
        if words.contains("on") || words.contains("start") { return false }
        return nil
    }

    private func resetCache() {
        cachedPid = nil
        cachedApp = nil
        forcedAXTree = false
        cachedMicElement = nil
        cachedCameraElement = nil
        cachedHandElement = nil
        cachedHangUpElement = nil
        lastScanAt = nil
        lastScanInCall = false
        lastValidatedAt = nil
        handRaisedState = false
    }

    /// Logs only when the situation changes, so a steady state isn't repeated
    /// every tick.
    private func note(_ state: String, _ message: @autoclosure () -> String, warn: Bool = false) {
        guard loggedState != state else { return }
        loggedState = state
        warn ? Log.warn("engine", message()) : Log.info("engine", message())
    }

    // MARK: - Public API

    /// Cheap on the common path (reads two cached AX attributes); only walks
    /// the AX tree when the cache is cold or has gone stale (call ended,
    /// Teams restarted).
    func pollStatus() -> Status {
        lock.lock(); defer { lock.unlock() }
        return _pollStatus()
    }

    private func _pollStatus(forceScan: Bool = false) -> Status {
        // Without Accessibility access every AX call just fails; say so by
        // reporting nothing rather than guessing.
        guard AXIsProcessTrusted() else {
            note("noAccess", "Accessibility access isn't granted (\(Permissions.accessibilityPaneName)) — can't read or control Teams", warn: true)
            resetCache()
            return .disconnected
        }
        guard let running = findRunningTeams() else {
            note("noTeams", "Teams isn't running")
            resetCache()
            return .disconnected
        }

        if cachedPid != running.processIdentifier {
            resetCache()
            cachedPid = running.processIdentifier
            cachedApp = AXUIElementCreateApplication(running.processIdentifier)
            Log.info("engine", "Teams found (pid \(running.processIdentifier))")
        }
        guard let app = cachedApp else { return .disconnected }
        forceAccessibilityTreeIfNeeded(app)

        let now = Date()

        // Fast path: cached button refs still valid and recently confirmed.
        let revalidationDue = lastValidatedAt.map { now.timeIntervalSince($0) > Self.revalidateInterval } ?? true
        if !revalidationDue, let status = readCached() { return status }

        // Cache cold, stale, or due for a re-check. Rescans are throttled;
        // in between, use what the cache still says, or the last conclusion.
        if !forceScan, let last = lastScanAt, now.timeIntervalSince(last) < Self.idleRescanInterval {
            if let status = readCached() { return status }
            return Status(inCall: lastScanInCall, micEnabled: false, cameraEnabled: false,
                          handRaised: lastScanInCall ? handRaisedState : false)
        }
        lastScanAt = now

        let previousMic = cachedMicElement
        cachedMicElement = nil
        cachedCameraElement = nil
        cachedHandElement = nil
        cachedHangUpElement = nil

        if let controls = scanForCallControls(in: app) {
            if let previousMic, let mic = controls.mic, !CFEqual(previousMic, mic) {
                Log.info("engine", "Call controls were redrawn by Teams — re-resolved the buttons")
            }
            cachedMicElement = controls.mic
            cachedCameraElement = controls.camera
            cachedHandElement = controls.hand
            cachedHangUpElement = controls.hangUp
            lastScanInCall = true
            lastValidatedAt = now

            if let status = readCached() {
                note("call", "Call detected (raise-hand button \(controls.hand == nil ? "missing" : "found"))")
                return status
            }
            // Found the buttons but couldn't make sense of their labels (e.g.
            // a language we don't parse): in a call, state unknown.
            let micLabel = controls.mic.flatMap { stringAttr($0, kAXDescriptionAttribute) } ?? "?"
            let camLabel = controls.camera.flatMap { stringAttr($0, kAXDescriptionAttribute) } ?? "?"
            note("unreadable", "Call controls found but their labels aren't understood — mic: \"\(micLabel)\", camera: \"\(camLabel)\"", warn: true)
            return Status(inCall: true, micEnabled: false, cameraEnabled: false, handRaised: handRaisedState)
        }

        // No toolbar found, but a window named like a meeting still means a
        // call whose controls we can't see right now (hidden, mid-join).
        let windowCount = windows(of: app).count
        if windows(of: app).contains(where: { title(of: $0).hasPrefix("Meeting") }) {
            lastScanInCall = true
            note("hidden", "A meeting window is open but its call controls aren't visible (\(windowCount) windows)")
            return Status(inCall: true, micEnabled: false, cameraEnabled: false, handRaised: handRaisedState)
        }

        lastScanInCall = false
        handRaisedState = false
        note("noCall", "Teams is running; no call controls found in \(windowCount) window(s)")
        return Status(inCall: false, micEnabled: false, cameraEnabled: false, handRaised: false)
    }

    private func readCached() -> Status? {
        guard let mic = cachedMicElement, let camera = cachedCameraElement,
              let micDesc = stringAttr(mic, kAXDescriptionAttribute),
              let camDesc = stringAttr(camera, kAXDescriptionAttribute),
              let micOn = micEnabled(fromDescription: micDesc),
              let camOn = cameraEnabled(fromDescription: camDesc) else { return nil }
        return Status(inCall: true, micEnabled: micOn, cameraEnabled: camOn, handRaised: handRaisedState)
    }

    // MARK: - Pressing buttons

    /// Presses a toolbar button, then waits for Teams to actually reflect it.
    /// Teams can take a beat to update a button's label, and may redraw the
    /// toolbar when it does, so the cache is dropped and the buttons are
    /// found afresh before reading the result. Returns the status as Teams
    /// finally reports it (which is also what we log if the press didn't take).
    private func press(_ element: AXUIElement, label: String, before: Status, changed: (Status) -> Bool) -> Status {
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result != .success {
            Log.warn("engine", "Pressing \(label) failed (AXError \(result.rawValue))")
        }

        var latest = before
        for attempt in 1...8 {
            Thread.sleep(forTimeInterval: attempt == 1 ? 0.15 : 0.2)
            cachedMicElement = nil
            cachedCameraElement = nil
            cachedHandElement = nil
            cachedHangUpElement = nil
            latest = _pollStatus(forceScan: true)
            if changed(latest) {
                Log.info("engine", "Pressed \(label): Teams reflected it after ~\(attempt == 1 ? 150 : 150 + (attempt - 1) * 200)ms")
                return latest
            }
        }
        Log.warn("engine", "Pressed \(label) but Teams still reports the old state after ~1.5s")
        return latest
    }

    @discardableResult
    func toggleMic() -> Status {
        lock.lock(); defer { lock.unlock() }
        let before = _pollStatus(forceScan: true)
        guard let mic = cachedMicElement else {
            Log.warn("engine", "Mic toggle requested but no call controls were found")
            return before
        }
        return press(mic, label: "mic button", before: before) { $0.micEnabled != before.micEnabled }
    }

    /// Mutes the mic only if it's currently live, so an auto-mute that races
    /// a manual mute can never flip you back to unmuted.
    @discardableResult
    func muteMicIfLive() -> Status {
        lock.lock(); defer { lock.unlock() }
        let before = _pollStatus(forceScan: true)
        guard before.inCall, before.micEnabled, let mic = cachedMicElement else { return before }
        return press(mic, label: "mic button (auto-mute)", before: before) { !$0.micEnabled }
    }

    @discardableResult
    func toggleCamera() -> Status {
        lock.lock(); defer { lock.unlock() }
        let before = _pollStatus(forceScan: true)
        guard let camera = cachedCameraElement else {
            Log.warn("engine", "Camera toggle requested but no call controls were found")
            return before
        }
        return press(camera, label: "camera button", before: before) { $0.cameraEnabled != before.cameraEnabled }
    }

    /// Presses Teams' Leave button, then waits for the call to actually end.
    /// (Leaving only — never "End meeting for everyone", which lives in the
    /// button's dropdown and is never pressed here.)
    @discardableResult
    func leaveCall() -> Status {
        lock.lock(); defer { lock.unlock() }
        let before = _pollStatus(forceScan: true)
        guard before.inCall, let hangUp = cachedHangUpElement else {
            Log.warn("engine", before.inCall ? "Hang up requested but the Leave button wasn't found" : "Hang up requested but there's no call")
            return before
        }
        let result = AXUIElementPerformAction(hangUp, kAXPressAction as CFString)
        if result != .success { Log.warn("engine", "Pressing Leave failed (AXError \(result.rawValue))") }

        for attempt in 1...12 {
            Thread.sleep(forTimeInterval: 0.25)
            cachedMicElement = nil
            cachedCameraElement = nil
            cachedHandElement = nil
            cachedHangUpElement = nil
            let latest = _pollStatus(forceScan: true)
            if !latest.inCall {
                Log.info("engine", "Left the call (controls gone after ~\(attempt * 250)ms)")
                return latest
            }
        }
        Log.warn("engine", "Pressed Leave but the call still looks active after 3s (Teams may be asking to confirm)")
        return _pollStatus()
    }

    /// Dumb toggle: presses Teams' raise-hand button and flips our own
    /// optimistic flag. Does not verify against Teams' real state (it isn't
    /// readable outside the People panel) — if Teams auto-lowers your hand,
    /// this won't notice until you press again.
    @discardableResult
    func toggleHand() -> Status {
        lock.lock(); defer { lock.unlock() }
        _ = _pollStatus(forceScan: true) // ensure cache is warm
        guard let hand = cachedHandElement else {
            Log.warn("engine", "Raise-hand requested but the button wasn't found")
            return _pollStatus()
        }
        let result = AXUIElementPerformAction(hand, kAXPressAction as CFString)
        if result != .success { Log.warn("engine", "Pressing raise-hand failed (AXError \(result.rawValue))") }
        handRaisedState.toggle()
        return _pollStatus()
    }

    // MARK: - Diagnostics

    /// A full, fresh look at what we can and can't see in Teams — for when
    /// something isn't working. Walks every window completely, so it's slower
    /// than a poll; call it on demand only.
    func diagnose() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }

        var report: [String: Any] = ["accessibilityTrusted": AXIsProcessTrusted()]
        guard let running = findRunningTeams() else {
            report["teamsRunning"] = false
            return report
        }
        report["teamsRunning"] = true
        report["teamsBundleId"] = running.bundleIdentifier ?? NSNull()
        report["teamsPid"] = Int(running.processIdentifier)
        if let url = running.bundleURL, let info = Bundle(url: url)?.infoDictionary {
            report["teamsVersion"] = info["CFBundleShortVersionString"] ?? NSNull()
        }

        let app = AXUIElementCreateApplication(running.processIdentifier)
        forceAccessibilityTreeIfNeeded(app)

        func describe(_ element: AXUIElement?, parse: (String) -> Bool?) -> [String: Any] {
            guard let element else { return ["found": false] }
            let label = stringAttr(element, kAXDescriptionAttribute)
            return [
                "found": true,
                "label": label ?? NSNull(),
                "parsedAsOn": label.flatMap(parse).map { $0 as Any } ?? NSNull(),
            ]
        }

        let allWindows = windows(of: app)
        report["windowCount"] = allWindows.count
        report["windows"] = allWindows.map { window -> [String: Any] in
            let (controls, nodes) = findControls(in: window, exhaustive: true)
            return [
                "title": title(of: window),
                "nodesScanned": nodes,
                "looksLikeACall": controls.isCall,
                "microphoneButton": describe(controls.mic, parse: micEnabled(fromDescription:)),
                "cameraButton": describe(controls.camera, parse: cameraEnabled(fromDescription:)),
                "raiseHandButton": describe(controls.hand, parse: { _ in nil }),
                "hangUpButton": describe(controls.hangUp, parse: { _ in nil }),
            ]
        }
        report["callDetected"] = allWindows.contains { findControls(in: $0).controls.isCall }
        if !AXIsProcessTrusted() {
            report["hint"] = "Accessibility isn't allowed for this app (macOS 27 calls the pane \"\(Permissions.accessibilityPaneName)\"). " + Permissions.staleGrantHint
        } else if allWindows.isEmpty {
            report["hint"] = "Teams reports no windows to Accessibility — relaunch Teams if it persists."
        }
        return report
    }
}
