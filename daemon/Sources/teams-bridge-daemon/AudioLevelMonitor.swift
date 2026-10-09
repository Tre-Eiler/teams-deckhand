import AVFoundation
import CoreAudio
import Foundation

/// Watches an input device's loudness to detect when you're talking. It only
/// ever measures level — audio is never stored or sent anywhere.
///
/// Teams' own mute is software-level, so the raw mic signal is still there
/// when you're muted; that's why this can run independently of Teams.
///
/// Speech = louder than the room's noise floor by `marginDb`. The floor is
/// tracked adaptively (drops fast, rises very slowly) so it works across
/// mics, gain settings and rooms without per-user tuning.
///
/// Captures straight from the CoreAudio device (not AVAudioEngine): choosing
/// a specific device on an engine's input node makes it post configuration
/// changes that, handled by restarting, loop forever.
final class AudioLevelMonitor {
    private let lock = NSLock()
    private let captureQueue = DispatchQueue(label: "teams-bridge.audio-level", qos: .userInitiated)

    private var wantRunning = false
    private var capture: (device: AudioDeviceID, proc: AudioDeviceIOProcID)?
    private var startedAt: Date?
    private var pendingRestart: DispatchWorkItem?

    private var _lastSignalAt: Date?
    private var _lastSpeechAt: Date?
    private var _levelDb = -120.0
    private var _noiseFloorDb: Double?
    private var _marginDb = AutoMuteSettings.defaultMarginDb
    private var _lastError: String?
    private var _preferredInput: String?
    private var _inUseInput: String?

    // Never treat anything quieter than this as speech, however low the floor.
    private static let absoluteThresholdDb = -55.0
    private static let floorFallRate = 0.15 // follows quiet moments quickly
    private static let floorRiseRate = 0.0008 // creeps up so speech doesn't become "the floor"
    // Right after starting, the floor has only seen the first (often quiet)
    // buffers; let it climb to the room's real level fast, otherwise ordinary
    // room noise would count as speech for the first half minute.
    private static let warmupSeconds: TimeInterval = 8
    private static let warmupRiseRate = 0.02
    // Any live mic has self-noise well above this; exact digital silence
    // means no signal is actually reaching us.
    private static let signalPresentDb = -130.0
    private static let signalGrace: TimeInterval = 3

    init() {
        // Plugging/unplugging mics or changing the default can change which
        // device we should be on.
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
                self?.scheduleRestart()
            }
        }
    }

    // MARK: - Reading

    var lastSpeechAt: Date? { lock.withLock { _lastSpeechAt } }

    /// True only while we're capturing *and* actually receiving signal. When
    /// false there's no way to tell whether you're talking (no permission,
    /// device silent or missing), so callers must not act on `lastSpeechAt`.
    var isListening: Bool { lock.withLock { receivingSignal() } }

    struct Snapshot {
        var levelDb: Double
        var noiseFloorDb: Double?
        var thresholdDb: Double
        var capturing: Bool
        var receivingSignal: Bool
        var inputDevice: String?
        var authorization: String
        var lastError: String?
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(
                levelDb: _levelDb,
                noiseFloorDb: _noiseFloorDb,
                thresholdDb: threshold(),
                capturing: capture != nil,
                receivingSignal: receivingSignal(),
                inputDevice: _inUseInput,
                authorization: Self.authorizationName(),
                lastError: _lastError
            )
        }
    }

    func setMargin(_ db: Double) {
        lock.withLock { _marginDb = db }
    }

    /// Which input to listen to: a case-insensitive part of its name, or
    /// nil/empty for the system default. Set it to your Teams mic if that
    /// isn't the system default — listening to the wrong device would see
    /// silence while you talk.
    func setPreferredInput(_ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        let normalized = (trimmed?.isEmpty ?? true) ? nil : trimmed
        let changed: Bool = lock.withLock {
            guard _preferredInput != normalized else { return false }
            _preferredInput = normalized
            return true
        }
        if changed { scheduleRestart() }
    }

    // MARK: - Lifecycle

    /// Shows the system permission prompt now (if it hasn't been answered)
    /// so it appears when you switch auto-mute on, not mid-call.
    func requestAccessIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    /// Idempotent; call as often as you like. Only holds the mic open while
    /// it's actually needed (auto-mute on and in a call).
    func setRunning(_ run: Bool) {
        let changed: Bool = lock.withLock {
            guard wantRunning != run else { return false }
            wantRunning = run
            return true
        }
        guard changed else { return }
        run ? start() : stop()
    }

    /// Debounced, and a no-op unless the device we should be on has actually
    /// changed — starting a Bluetooth mic reshuffles the device list, which
    /// would otherwise bounce us in a loop.
    private func scheduleRestart() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lock.withLock({ self.wantRunning }) else { return }
            let current = self.lock.withLock { self.capture?.device }
            if let target = self.resolveDevice().device, target.id == current { return }
            self.stop()
            self.start()
        }
        lock.withLock {
            pendingRestart?.cancel()
            pendingRestart = work
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func start() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.lock.withLock({ self.wantRunning }) else { return }
                    granted ? self.startCapture() : self.recordError("Microphone access was denied")
                }
            }
        default:
            recordError("Microphone access is denied — enable it in System Settings > Privacy & Security > Microphone")
        }
    }

    /// A named device that isn't present is an error, not a cue to fall back
    /// to the default: that would silently watch the wrong mic.
    private func resolveDevice() -> (device: InputDevice?, error: String?) {
        if let wanted = lock.withLock({ _preferredInput }) {
            if let device = AudioDevices.input(matching: wanted) { return (device, nil) }
            return (nil, "No input device matching \"\(wanted)\" is connected")
        }
        if let device = AudioDevices.defaultInput() { return (device, nil) }
        return (nil, "No input device available")
    }

    private func startCapture() {
        guard lock.withLock({ capture == nil }) else { return }

        let resolved = resolveDevice()
        guard let device = resolved.device else {
            recordError(resolved.error ?? "No input device available")
            return
        }
        guard AudioDevices.deliversFloat32(device.id) else {
            recordError("Input \"\(device.name)\" uses an unsupported sample format")
            return
        }

        var procID: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&procID, device.id, captureQueue) { [weak self] _, input, _, _, _ in
            self?.process(input)
        }
        guard created == noErr, let procID else {
            recordError("Couldn't open \"\(device.name)\" (error \(created))")
            return
        }
        let started = AudioDeviceStart(device.id, procID)
        guard started == noErr else {
            AudioDeviceDestroyIOProcID(device.id, procID)
            recordError("Couldn't start \"\(device.name)\" (error \(started))")
            return
        }

        lock.withLock {
            capture = (device.id, procID)
            _inUseInput = device.name
            startedAt = Date()
            _lastSignalAt = nil
            _noiseFloorDb = nil
            _lastError = nil
        }
        Log.info("audio", "Listening on \"\(device.name)\"")
    }

    private func stop() {
        let old: (device: AudioDeviceID, proc: AudioDeviceIOProcID)? = lock.withLock {
            let c = capture
            capture = nil
            _inUseInput = nil
            _levelDb = -120
            return c
        }
        guard let old else { return }
        AudioDeviceStop(old.device, old.proc)
        AudioDeviceDestroyIOProcID(old.device, old.proc)
        Log.info("audio", "Stopped listening")
    }

    private func recordError(_ message: String) {
        let isNew: Bool = lock.withLock {
            let changed = _lastError != message
            _lastError = message
            return changed
        }
        if isNew { Log.warn("audio", message) }
    }

    // MARK: - Analysis (audio thread)

    private func process(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var sumSquares: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            for i in 0..<n { sumSquares += samples[i] * samples[i] }
            count += n
        }
        guard count > 0 else { return }
        let db = 20 * log10(Double(max((sumSquares / Float(count)).squareRoot(), 1e-7)))

        lock.withLock {
            _levelDb = db
            guard db > Self.signalPresentDb else { return } // digital silence: nothing to learn from
            _lastSignalAt = Date()

            if let floor = _noiseFloorDb {
                let warmingUp = startedAt.map { Date().timeIntervalSince($0) < Self.warmupSeconds } ?? false
                let rate = db < floor ? Self.floorFallRate : (warmingUp ? Self.warmupRiseRate : Self.floorRiseRate)
                _noiseFloorDb = floor + (db - floor) * rate
            } else {
                _noiseFloorDb = db
            }
            if db > threshold() { _lastSpeechAt = Date() }
        }
    }

    // MARK: - Private (call with lock held)

    private func receivingSignal() -> Bool {
        guard capture != nil else { return false }
        let now = Date()
        if let signal = _lastSignalAt { return now.timeIntervalSince(signal) < Self.signalGrace }
        // Just started and nothing has arrived yet: give it a moment.
        return startedAt.map { now.timeIntervalSince($0) < Self.signalGrace } ?? false
    }

    private func threshold() -> Double {
        max((_noiseFloorDb ?? -70) + _marginDb, Self.absoluteThresholdDb)
    }

    private static func authorizationName() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}
