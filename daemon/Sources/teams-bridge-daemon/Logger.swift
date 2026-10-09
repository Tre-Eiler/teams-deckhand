import Foundation
import os

/// Small rotating file log (also mirrored to the unified log, so it shows in
/// Console.app). Meant for events — state changes, commands, errors — not a
/// firehose, so a few MB of history covers days of use.
///
/// Privacy: never log meeting names/window titles, audio, or anything
/// personal. (The on-demand diagnostics report does include window titles;
/// that's an explicit user action, not something written here.)
enum Log {
    static let directory: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/TeamsBridge", isDirectory: true)
    static var currentFile: URL { directory.appendingPathComponent("teams-bridge.log") }

    private static let maxBytes = 1_000_000
    private static let keptFiles = 3 // teams-bridge.log, .1, .2
    private static let queue = DispatchQueue(label: "teams-bridge.log")
    private static let unified = Logger(subsystem: "com.teams-bridge.daemon", category: "daemon")

    static func info(_ category: String, _ message: String) { write("INFO ", category, message) }
    static func warn(_ category: String, _ message: String) { write("WARN ", category, message) }
    static func error(_ category: String, _ message: String) { write("ERROR", category, message) }

    /// The last `maxLines` lines of the current log, for quick looks.
    static func tail(_ maxLines: Int) -> String {
        queue.sync {
            guard let text = try? String(contentsOf: currentFile, encoding: .utf8) else { return "" }
            return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(maxLines).joined(separator: "\n")
        }
    }

    /// Every log file that exists, newest first — what an export bundles.
    static func existingFiles() -> [URL] {
        queue.sync {
            (0..<keptFiles).map(fileURL).filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    // MARK: - Private

    private static func write(_ level: String, _ category: String, _ message: String) {
        switch level {
        case "ERROR": unified.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        case "WARN ": unified.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        default: unified.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        }

        queue.async {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = .current
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let line = "\(formatter.string(from: Date())) \(level) [\(category)] \(message)\n"

            let fm = FileManager.default
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded(fm)

            if !fm.fileExists(atPath: currentFile.path) {
                fm.createFile(atPath: currentFile.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: currentFile) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }

    private static func fileURL(_ index: Int) -> URL {
        index == 0 ? currentFile : directory.appendingPathComponent("teams-bridge.log.\(index)")
    }

    private static func rotateIfNeeded(_ fm: FileManager) {
        let size = (try? fm.attributesOfItem(atPath: currentFile.path)[.size] as? Int) ?? 0
        guard size > maxBytes else { return }
        try? fm.removeItem(at: fileURL(keptFiles - 1))
        for index in stride(from: keptFiles - 2, through: 0, by: -1) {
            try? fm.moveItem(at: fileURL(index), to: fileURL(index + 1))
        }
    }
}
