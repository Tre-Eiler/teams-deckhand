import AppKit
import ApplicationServices
import Foundation
import UniformTypeIdentifiers

// TEAMS_BRIDGE_DEV_PORT lets a test build run beside the installed app (and
// skips the Accessibility prompt so it doesn't pop dialogs while testing).
let devPort = ProcessInfo.processInfo.environment["TEAMS_BRIDGE_DEV_PORT"].flatMap { in_port_t($0) }
let bridgePort: in_port_t = devPort ?? 8942

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = TeamsAutomationEngine()
    private let server = BridgeServer()
    private let autoMute = AutoMuteController()
    private let audio = AudioLevelMonitor()
    private var statusMenu: StatusMenu?
    private var pollTimer: Timer?
    private var lastStatus: Status = .disconnected
    private var lastHealth = Health()
    private var handAutoLowerTimer: Timer?
    private static let handRaisedDuration: TimeInterval = 5
    /// While set and in the future, the mic is monitored regardless of call
    /// state (see GET /automute/listen).
    private var listenUntil: Date?
    private var lastHearing: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if devPort == nil { ensureAccessibilityTrusted() }

        audio.setMargin(autoMute.settings.speechMarginDb)
        audio.setPreferredInput(autoMute.settings.inputDeviceName)
        lastStatus = autoMute.decorate(.disconnected)

        statusMenu = StatusMenu()
        statusMenu?.onCopyDiagnostics = { [weak self] in self?.copyDiagnosticsToClipboard() }
        statusMenu?.onExportLogs = { [weak self] in self?.exportLogs() }
        statusMenu?.onResetPermission = {
            Log.info("app", "Resetting the Accessibility permission and asking again")
            Log.info("app", Permissions.resetAccessibilityAndAskAgain())
            NSWorkspace.shared.open(Permissions.accessibilitySettingsURL)
        }
        statusMenu?.onRestart = {
            Log.info("app", "Restarting")
            Permissions.restartViaLaunchd()
        }
        statusMenu?.update(lastStatus, health: lastHealth)

        server.statusProvider = { [weak self] in self?.lastStatus ?? .disconnected }
        server.onMicToggle = { [weak self] in
            Log.info("command", "Mic toggle")
            return self?.applyAndSync(self?.engine.toggleMic()) ?? .disconnected
        }
        server.onCameraToggle = { [weak self] in
            Log.info("command", "Camera toggle")
            return self?.applyAndSync(self?.engine.toggleCamera()) ?? .disconnected
        }
        server.onLeaveCall = { [weak self] in
            Log.info("command", "Hang up")
            return self?.applyAndSync(self?.engine.leaveCall()) ?? .disconnected
        }
        server.onHandToggle = { [weak self] in
            Log.info("command", "Raise hand")
            return self?.handleHandToggle() ?? .disconnected
        }
        server.onAutoMuteToggle = { [weak self] in self?.runAutoMuteCommand { $0.toggleEnabled() } ?? .disconnected }
        server.onAutoMuteTimeout = { [weak self] seconds in self?.runAutoMuteCommand { $0.setTimeout(seconds) } ?? .disconnected }
        server.onAutoMuteAddTime = { [weak self] seconds in self?.runAutoMuteCommand { $0.addTime(seconds) } ?? .disconnected }
        server.onAutoMuteMargin = { [weak self] db in
            self?.autoMute.setSpeechMargin(db)
            self?.audio.setMargin(self?.autoMute.settings.speechMarginDb ?? AutoMuteSettings.defaultMarginDb)
        }
        server.onAutoMuteInput = { [weak self] name in
            self?.autoMute.setInputDeviceName(name)
            self?.audio.setPreferredInput(self?.autoMute.settings.inputDeviceName)
        }
        server.onAutoMuteListen = { [weak self] seconds in
            self?.listenUntil = Date().addingTimeInterval(TimeInterval(seconds))
            self?.audio.requestAccessIfNeeded()
        }
        server.autoMuteDetails = { [weak self] in self?.autoMuteDetails() ?? [:] }
        server.diagnostics = { [weak self] in self?.diagnosticsReport() ?? [:] }
        server.logArchive = { [weak self] in self?.buildLogArchive() }

        do {
            try server.start(port: bridgePort)
            print("teams-bridge-daemon listening on port \(bridgePort)")
        } catch {
            print("Failed to start server on port \(bridgePort): \(error)")
            Log.error("app", "Couldn't start the server on port \(bridgePort): \(error)")
        }
        logStartup()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    private func poll() {
        let base = engine.pollStatus()
        let diagnosticListen = (listenUntil ?? .distantPast) > Date()
        let audioWanted = (autoMute.settings.enabled && base.inCall) || diagnosticListen
        audio.setRunning(audioWanted)

        let hearingNow = audio.isListening
        // `listening` is false when we can't actually hear the mic (permission
        // pending/denied, no input device, silent device): the countdown then
        // holds rather than run — auto-mute must never fire while it's blind.
        let status = autoMute.tick(base: base, lastSpeechAt: audio.lastSpeechAt, listening: hearingNow) {
            engine.muteMicIfLive()
        }

        let hearing = hearingNow
        if audioWanted, hearing != lastHearing {
            Log.info("audio", hearing ? "Microphone signal present" : "No microphone signal — auto-mute holds instead of muting")
        }
        lastHearing = audioWanted ? hearing : nil

        let health = Health(accessibilityTrusted: engine.isAccessibilityTrusted, teamsRunning: engine.isTeamsRunning)
        if health != lastHealth {
            if health.accessibilityTrusted != lastHealth.accessibilityTrusted {
                Log.info("app", health.accessibilityTrusted ? "Accessibility access granted" : "Accessibility access missing")
            }
            lastHealth = health
            statusMenu?.update(lastStatus, health: health)
        }
        sync(status)
    }

    /// Called from the toggle handlers, which run on Swifter's background
    /// thread. The caller already has the fresh `status` it needs for the
    /// HTTP response; this just gets menu/broadcast side effects onto the
    /// main thread without making the response wait for them.
    @discardableResult
    private func applyAndSync(_ status: Status?) -> Status {
        guard let status = status else { return lastStatus }
        let decorated = autoMute.decorate(status)
        DispatchQueue.main.async { [weak self] in
            self?.sync(decorated)
        }
        return decorated
    }

    /// Applies an auto-mute setting change and returns/broadcasts the result
    /// straight away rather than waiting for the next poll tick.
    private func runAutoMuteCommand(_ command: (AutoMuteController) -> Void) -> Status {
        command(autoMute)
        if autoMute.settings.enabled { audio.requestAccessIfNeeded() }
        return applyAndSync(lastStatus)
    }

    /// Hand-raise state isn't reliably readable back from Teams (see
    /// TeamsAutomationEngine), so instead of a plain toggle this is a timed
    /// action: press raises and auto-lowers itself after
    /// `handRaisedDuration`. Pressing again before then lowers it early and
    /// cancels the pending auto-lower.
    private func handleHandToggle() -> Status {
        let status = autoMute.decorate(engine.toggleHand())
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.sync(status)
            self.handAutoLowerTimer?.invalidate()
            self.handAutoLowerTimer = nil
            guard status.handRaised else { return }
            self.handAutoLowerTimer = Timer.scheduledTimer(withTimeInterval: Self.handRaisedDuration, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.handAutoLowerTimer = nil
                self.sync(self.autoMute.decorate(self.engine.toggleHand()))
            }
        }
        return status
    }

    private func autoMuteDetails() -> [String: Any] {
        let settings = autoMute.settings
        let audio = self.audio.snapshot()
        func round1(_ x: Double) -> Double { (x * 10).rounded() / 10 }
        return [
            "enabled": settings.enabled,
            "timeoutSeconds": settings.timeoutSeconds,
            "speechMarginDb": settings.speechMarginDb,
            "capturing": audio.capturing,
            "listening": audio.receivingSignal,
            "inputDevice": audio.inputDevice ?? NSNull(),
            "preferredInput": settings.inputDeviceName ?? NSNull(),
            "availableInputs": AudioDevices.inputs().map(\.name),
            "microphoneAuthorization": audio.authorization,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "levelDb": round1(audio.levelDb),
            "noiseFloorDb": audio.noiseFloorDb.map(round1) ?? NSNull(),
            "thresholdDb": round1(audio.thresholdDb),
            "error": audio.lastError ?? NSNull(),
        ]
    }

    /// Everything needed to debug "it doesn't work on this Mac" from a paste:
    /// versions, permissions, what Teams exposes (window titles, whether the
    /// call controls are found and their raw labels), and the audio side.
    private func diagnosticsReport() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let statusJSON = (try? JSONEncoder().encode(lastStatus))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [:]
        return [
            "app": [
                "version": info["CFBundleShortVersionString"] ?? "dev",
                "build": info["CFBundleVersion"] ?? "dev",
                "path": Bundle.main.bundlePath,
            ],
            "system": ["macOS": ProcessInfo.processInfo.operatingSystemVersionString, "arch": arch],
            "status": statusJSON,
            "teams": engine.diagnose(),
            "autoMute": autoMuteDetails(),
        ]
    }

    /// One line per meaningful change (not per second of countdown).
    private func logChanges(from old: Status, to new: Status) {
        if old.inCall != new.inCall { Log.info("state", new.inCall ? "Call started" : "Call ended") }
        guard new.inCall else { return }
        if old.micEnabled != new.micEnabled { Log.info("state", "Mic \(new.micEnabled ? "unmuted" : "muted")") }
        if old.cameraEnabled != new.cameraEnabled { Log.info("state", "Camera \(new.cameraEnabled ? "on" : "off")") }
        if old.handRaised != new.handRaised { Log.info("state", "Hand \(new.handRaised ? "raised" : "lowered")") }
    }

    private func logStartup() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] ?? "dev") (\(info["CFBundleVersion"] ?? "dev"))"
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        let settings = autoMute.settings
        Log.info("app", "Teams Bridge \(version) starting — \(ProcessInfo.processInfo.operatingSystemVersionString), \(arch)")
        Log.info("app", "Accessibility \(engine.isAccessibilityTrusted ? "granted" : "NOT granted"); microphone \(audio.snapshot().authorization); Teams \(engine.isTeamsRunning ? "running" : "not running")")
        Log.info("app", "Auto-mute \(settings.enabled ? "on" : "off"), timeout \(settings.timeoutSeconds)s, input \(settings.inputDeviceName ?? "system default")")
    }

    /// Zips the log files and a diagnostics report into a temp file, ready to
    /// hand over. The report includes Teams window titles, so this is only
    /// ever triggered explicitly (menu item, or a request from this Mac).
    private func buildLogArchive() -> URL? {
        let stamp: String = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HHmm"
            return f.string(from: Date())
        }()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("TeamsBridgeLogs-\(UUID().uuidString)", isDirectory: true)
        let stage = root.appendingPathComponent("Teams Bridge Logs", isDirectory: true)
        let archive = fm.temporaryDirectory.appendingPathComponent("Teams Bridge Logs \(stamp) \(UUID().uuidString.prefix(6)).zip")
        defer { try? fm.removeItem(at: root) }
        try? fm.createDirectory(at: stage, withIntermediateDirectories: true)

        for file in Log.existingFiles() {
            try? fm.copyItem(at: file, to: stage.appendingPathComponent(file.lastPathComponent))
        }
        if let data = try? JSONSerialization.data(withJSONObject: diagnosticsReport(), options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stage.appendingPathComponent("diagnostics.json"))
        }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", "--norsrc", "--noextattr", "--noqtn", stage.path, archive.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            Log.error("app", "Couldn't create the log export: \(error)")
            return nil
        }
        guard ditto.terminationStatus == 0 else {
            Log.error("app", "Log export failed (ditto exit \(ditto.terminationStatus))")
            return nil
        }
        return archive
    }

    /// Menu action: pick where to save the zip, then show it in Finder.
    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Teams Bridge Logs \(Date().formatted(.iso8601.year().month().day())).zip"
        panel.allowedContentTypes = [.zip]
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Saves the log files plus a diagnostics report (which includes your Teams window titles) as a zip."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        Log.info("app", "Exporting logs")
        guard let archive = buildLogArchive() else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        do {
            try fm.moveItem(at: archive, to: destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            Log.error("app", "Couldn't save the log export to \(destination.path): \(error)")
        }
    }

    private func copyDiagnosticsToClipboard() {
        let report = diagnosticsReport()
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func sync(_ status: Status) {
        guard status != lastStatus else { return }
        logChanges(from: lastStatus, to: status)
        lastStatus = status
        statusMenu?.update(status, health: lastHealth)
        server.broadcast(status)
    }

    private func ensureAccessibilityTrusted() {
        let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
