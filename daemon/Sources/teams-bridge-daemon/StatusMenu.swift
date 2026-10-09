import AppKit

/// What the app can currently do, independent of any call — shown in the menu
/// so a missing permission isn't a silent failure.
struct Health: Equatable {
    var accessibilityTrusted = true
    var teamsRunning = true
}

/// Minimal menu bar presence — no Dock icon. Shows at a glance whether the
/// daemon sees a call, says what's wrong when it doesn't work, and offers
/// the fix or a diagnostics dump.
final class StatusMenu: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let detailItem = NSMenuItem(title: "Status: —", action: nil, keyEquivalent: "")
    private let problemItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let resetItem = NSMenuItem(title: "Reset Permission & Ask Again\u{2026}", action: nil, keyEquivalent: "")

    var onCopyDiagnostics: (() -> Void)?
    var onExportLogs: (() -> Void)?
    var onResetPermission: (() -> Void)?
    var onRestart: (() -> Void)?

    override init() {
        super.init()
        statusItem.button?.title = "○"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Deckhand", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        detailItem.isEnabled = false
        menu.addItem(detailItem)

        problemItem.target = self
        problemItem.isHidden = true
        menu.addItem(problemItem)

        // Shown only while permission is missing: the fix for a grant that
        // looks switched on in Settings but is stale (see Permissions).
        resetItem.target = self
        resetItem.action = #selector(resetPermission)
        resetItem.isHidden = true
        menu.addItem(resetItem)
        menu.addItem(.separator())

        let exportItem = NSMenuItem(title: "Export Logs\u{2026}", action: #selector(exportLogs), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)

        let folderItem = NSMenuItem(title: "Open Log Folder", action: #selector(openLogFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)

        let diagnosticsItem = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        diagnosticsItem.target = self
        menu.addItem(diagnosticsItem)

        // Only present when running from the installed app, which bundles the
        // plugin: lets you reinstall it (e.g. after reinstalling Stream Deck).
        if Self.bundledPluginURL != nil {
            let pluginItem = NSMenuItem(title: "Install Stream Deck Plugin\u{2026}", action: #selector(installPlugin), keyEquivalent: "")
            pluginItem.target = self
            menu.addItem(pluginItem)
        }
        menu.addItem(.separator())

        let restartItem = NSMenuItem(title: "Restart Deckhand", action: #selector(restart), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func update(_ status: Status, health: Health) {
        let icon: String
        if !health.accessibilityTrusted {
            icon = "\u{26A0}\u{FE0F}" // warning sign
        } else if !status.inCall {
            icon = "○"
        } else if !status.micEnabled {
            icon = "\u{1F507}" // muted speaker
        } else {
            icon = "\u{1F3A4}" // microphone
        }
        statusItem.button?.title = icon

        let autoMute = status.autoMuteEnabled
            ? "on (\(status.autoMuteRemainingSeconds.map { "\($0)s left" } ?? "idle"))"
            : "off"
        detailItem.title = "In call: \(status.inCall)  Mic: \(status.micEnabled)  Camera: \(status.cameraEnabled)  Hand: \(status.handRaised)  Auto-mute: \(autoMute)"

        resetItem.isHidden = health.accessibilityTrusted

        // The most useful thing to say right now, in order of how blocking it is.
        if !health.accessibilityTrusted {
            show(problem: "\u{26A0}\u{FE0F} Allow Deckhand in Privacy & Security \u{2192} \(Permissions.accessibilityPaneName)\u{2026}", actionable: true)
        } else if !health.teamsRunning {
            show(problem: "Teams isn't running", actionable: false)
        } else if status.autoMuteHolding {
            show(problem: "Auto-mute paused: can't hear the microphone", actionable: false)
        } else if !status.inCall {
            show(problem: "No Teams call detected", actionable: false)
        } else {
            problemItem.isHidden = true
        }
    }

    private func show(problem: String, actionable: Bool) {
        problemItem.title = problem
        problemItem.isEnabled = actionable
        problemItem.action = actionable ? #selector(openAccessibilitySettings) : nil
        problemItem.isHidden = false
    }

    private static var bundledPluginURL: URL? {
        Bundle.main.url(forResource: "Deckhand", withExtension: "streamDeckPlugin")
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(Permissions.accessibilitySettingsURL)
    }

    @objc private func resetPermission() {
        onResetPermission?()
    }

    @objc private func restart() {
        onRestart?()
    }

    @objc private func exportLogs() {
        onExportLogs?()
    }

    @objc private func openLogFolder() {
        try? FileManager.default.createDirectory(at: Log.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Log.directory)
    }

    @objc private func copyDiagnostics() {
        onCopyDiagnostics?()
    }

    @objc private func installPlugin() {
        if let url = Self.bundledPluginURL { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
