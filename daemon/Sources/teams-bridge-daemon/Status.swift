import Foundation

struct Status: Equatable, Codable {
    var inCall: Bool
    var micEnabled: Bool
    var cameraEnabled: Bool
    /// Optimistic only: flips when *we* press the raise-hand button. Teams
    /// doesn't expose real hand-raised state anywhere except the People
    /// panel's AX tree, so this can drift if Teams auto-lowers your hand —
    /// accepted tradeoff, see README.
    var handRaised: Bool

    /// Whether the auto-mute feature is switched on.
    var autoMuteEnabled: Bool = false
    /// The active auto-mute timeout, in seconds of silence.
    var autoMuteTimeoutSeconds: Int = AutoMuteSettings.defaultTimeoutSeconds
    /// Seconds left before auto-mute fires; nil whenever no countdown is
    /// running (feature off, not in a call, or mic already muted).
    var autoMuteRemainingSeconds: Int?
    /// True while a countdown is on hold because the daemon can't hear the
    /// mic (no permission, device missing or silent) — it never mutes blind.
    var autoMuteHolding: Bool = false

    static let disconnected = Status(inCall: false, micEnabled: false, cameraEnabled: false, handRaised: false)
}
