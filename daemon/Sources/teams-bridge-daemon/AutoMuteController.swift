import Foundation

struct AutoMuteSettings: Codable, Equatable {
    static let defaultTimeoutSeconds = 30
    static let timeoutRange = 1...3600
    static let defaultMarginDb = 12.0

    var enabled = false
    var timeoutSeconds = AutoMuteSettings.defaultTimeoutSeconds
    /// How far above the measured room-noise floor a sound must be to count
    /// as speech. Raise it if background noise keeps resetting the countdown;
    /// lower it if quiet talking gets missed.
    var speechMarginDb = AutoMuteSettings.defaultMarginDb
    /// Part of the name of the mic to listen to; nil means the system default.
    var inputDeviceName: String?
}

/// Persists settings as JSON so the on/off switch and chosen timeout survive
/// daemon restarts. Pass nil for an in-memory-only store (tests).
struct AutoMuteSettingsStore {
    let fileURL: URL?

    static var `default`: AutoMuteSettingsStore {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TeamsBridge", isDirectory: true)
        return AutoMuteSettingsStore(fileURL: dir.appendingPathComponent("settings.json"))
    }

    func load() -> AutoMuteSettings {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AutoMuteSettings.self, from: data) else {
            return AutoMuteSettings()
        }
        return settings
    }

    func save(_ settings: AutoMuteSettings) {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

/// Decides when to auto-mute the mic: while enabled, in a call, and live, a
/// countdown of (timeout + any added bonus) runs from the last moment speech
/// was heard. When it hits zero the mic is muted.
///
/// "Add time" grows a bonus that stays on top of the timeout until the mic is
/// muted (by auto-mute or by hand) or the feature is switched off — it
/// temporarily lengthens the countdown without touching the saved timeout.
final class AutoMuteController {
    private let lock = NSLock()
    private let now: () -> Date
    private let store: AutoMuteSettingsStore
    private let log: (String) -> Void

    private var _settings: AutoMuteSettings
    private var countdownStart: Date?
    private var bonusSeconds = 0
    private var holding = false

    init(
        store: AutoMuteSettingsStore = .default,
        now: @escaping () -> Date = Date.init,
        log: @escaping (String) -> Void = { Log.info("automute", $0) }
    ) {
        self.store = store
        self.now = now
        self.log = log
        self._settings = store.load()
    }

    var settings: AutoMuteSettings { lock.withLock { _settings } }

    // MARK: - Commands

    func toggleEnabled() {
        lock.withLock {
            _settings.enabled.toggle()
            log("Auto-mute switched \(_settings.enabled ? "on" : "off")")
            if !_settings.enabled { stopCountdown() }
            store.save(_settings)
        }
    }

    /// Selects the active timeout and restarts the countdown from it.
    func setTimeout(_ seconds: Int) {
        lock.withLock {
            _settings.timeoutSeconds = Self.clampTimeout(seconds)
            log("Timeout set to \(_settings.timeoutSeconds)s")
            if countdownStart != nil {
                countdownStart = now()
                bonusSeconds = 0
            }
            store.save(_settings)
        }
    }

    func setSpeechMargin(_ db: Double) {
        lock.withLock {
            _settings.speechMarginDb = min(max(db, 3), 40)
            store.save(_settings)
        }
    }

    func setInputDeviceName(_ name: String?) {
        lock.withLock {
            let trimmed = name?.trimmingCharacters(in: .whitespaces)
            _settings.inputDeviceName = (trimmed?.isEmpty ?? true) ? nil : trimmed
            store.save(_settings)
        }
    }

    /// Returns false (and does nothing) when there's no countdown to extend.
    @discardableResult
    func addTime(_ seconds: Int) -> Bool {
        lock.withLock {
            guard countdownStart != nil else { return false }
            bonusSeconds = min(bonusSeconds + max(seconds, 0), 3600)
            log("Added \(seconds)s to the countdown (bonus now \(bonusSeconds)s)")
            return true
        }
    }

    // MARK: - Evaluation

    /// Call regularly with the freshly polled status. Starts/stops/resets the
    /// countdown, fires the mute when it expires, and returns the status with
    /// the auto-mute fields filled in.
    ///
    /// `listening` says whether we can actually hear the mic. When we can't,
    /// there's no way to know if you're talking, so the countdown is held at
    /// full instead of running — it must never mute you blind.
    func tick(base: Status, lastSpeechAt: Date?, listening: Bool, mute: () -> Status) -> Status {
        let expired: Bool = lock.withLock {
            let t = now()
            let wasCounting = countdownStart != nil
            let wasHolding = holding

            guard _settings.enabled, base.inCall, base.micEnabled else {
                if wasCounting {
                    let why = !_settings.enabled ? "auto-mute is off" : (!base.inCall ? "call ended" : "mic is muted")
                    log("Countdown stopped (\(why))")
                }
                stopCountdown()
                return false
            }
            holding = !listening
            if countdownStart == nil || holding {
                countdownStart = t
            } else if let spoke = lastSpeechAt, let start = countdownStart, spoke > start {
                countdownStart = min(spoke, t)
            }

            if !wasCounting { log("Countdown started: \(_settings.timeoutSeconds)s of silence") }
            if holding != wasHolding && wasCounting {
                log(holding ? "Countdown held: can't hear the microphone" : "Countdown resumed: microphone audible again")
            }
            let isExpired = remaining(at: t) <= 0
            if isExpired { log("Silence for \(_settings.timeoutSeconds + bonusSeconds)s: muting the microphone") }
            return isExpired
        }

        guard expired else { return decorate(base) }

        let after = mute()
        lock.withLock { stopCountdown() }
        return decorate(after)
    }

    /// Fills in the auto-mute fields without advancing any state.
    func decorate(_ base: Status) -> Status {
        lock.withLock {
            var status = base
            status.autoMuteEnabled = _settings.enabled
            status.autoMuteTimeoutSeconds = _settings.timeoutSeconds
            status.autoMuteRemainingSeconds = countdownStart == nil
                ? nil
                : Int(remaining(at: now()).rounded(.up))
            status.autoMuteHolding = holding && countdownStart != nil
            return status
        }
    }

    // MARK: - Private (call with lock held)

    private func stopCountdown() {
        countdownStart = nil
        bonusSeconds = 0
        holding = false
    }

    private func remaining(at t: Date) -> TimeInterval {
        guard let start = countdownStart else { return 0 }
        return max(0, start.addingTimeInterval(TimeInterval(_settings.timeoutSeconds + bonusSeconds)).timeIntervalSince(t))
    }

    static func clampTimeout(_ seconds: Int) -> Int {
        let range = AutoMuteSettings.timeoutRange
        return min(max(seconds, range.lowerBound), range.upperBound)
    }
}
