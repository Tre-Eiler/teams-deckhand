import ApplicationServices
import Foundation

/// Accessibility permission plumbing, including the parts that differ by
/// macOS version and the recovery for a stale grant.
enum Permissions {
    static let bundleID = "com.teams-bridge.daemon"

    /// macOS 27 renamed the Accessibility pane to "Device Control and Data
    /// Access" (same list, same deep link). Say the name the user will
    /// actually see.
    static var accessibilityPaneName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control and Data Access" : "Accessibility"
    }

    static let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// macOS records an app's grant against its code signature. Our builds
    /// are ad-hoc signed, so every new build has a different signature: the
    /// old row stays in the list, switched on, but no longer matches — the app
    /// is denied while Settings shows it allowed. Flipping the toggle doesn't
    /// rewrite the row; resetting it and asking again does.
    static let staleGrantHint =
        "If \"Teams Bridge\" is already switched on in Privacy & Security → \(accessibilityPaneName) but this still shows as not allowed, the entry is stale (it was granted to an older build). Use \"Reset Permission & Ask Again\" in the menu bar menu."

    /// Resets our Accessibility entry and shows the system prompt again.
    /// Returns what `tccutil` said, for the log.
    @discardableResult
    static func resetAccessibilityAndAskAgain() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        var summary = "tccutil didn't run"
        do {
            try process.run()
            process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            summary = "tccutil exit \(process.terminationStatus): \(text)"
        } catch {
            summary = "tccutil failed to launch: \(error)"
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return summary
    }

    /// Relaunches the app through launchd. A running process can keep the
    /// permission state it started with, so this is the reliable way to pick
    /// up a freshly granted permission.
    static func restartViaLaunchd() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "-k", "gui/\(getuid())/\(bundleID)"]
        try? process.run()
    }
}
