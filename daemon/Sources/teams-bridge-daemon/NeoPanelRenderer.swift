import AppKit
import Foundation

/// What the person chose in the Status Panel's settings. The plugin sends
/// these with every request, so the panel is a pure function of
/// (status, options, time) like the key images.
struct NeoPanelOptions: Equatable {
    enum CountdownStyle: String {
        /// The panel fills with the state color and drains; text flips to dark
        /// while it sits over the fill.
        case fill
        /// A dim tint drains behind text that takes the state color.
        case tint
    }

    var showMic = true
    var showCamera = true
    var use24Hour = false
    var showCountdown = true
    /// The countdown takes over the panel only for this many final seconds.
    var countdownWindowSeconds = 10
    var countdownStyle: CountdownStyle = .fill
}

/// Renders the Stream Deck Neo info-strip panel (232x50) as a single
/// composited PNG: date/time in the system font (SF Pro — that's just what
/// NSFont.systemFont already is) plus SF Symbol status badges for
/// mic/camera, or, in the last seconds of an auto-mute countdown, the whole
/// panel as that countdown. The Neo action in the Stream Deck plugin fetches
/// this on a timer (for the clock) and whenever status changes.
enum NeoPanelRenderer {
    static let width: CGFloat = 232
    static let height: CGFloat = 50

    private static let background = NSColor(calibratedWhite: 0.07, alpha: 1)
    private static let primaryText = NSColor(calibratedWhite: 0.95, alpha: 1)
    private static let secondaryText = NSColor(calibratedWhite: 0.65, alpha: 1)
    private static let onFillText = NSColor(calibratedWhite: 0.07, alpha: 1)
    private static let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    private static let amber = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.10, alpha: 1)
    private static let red = NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)

    private static func timeFormatter(use24Hour: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    /// What the countdown face shows, or nil when the normal panel should.
    struct Countdown: Equatable {
        var fraction: CGFloat
        var label: String
        var value: String
        var color: NSColor
    }

    static func countdown(status: Status, options: NeoPanelOptions) -> Countdown? {
        guard options.showCountdown, status.autoMuteEnabled,
              let remaining = status.autoMuteRemainingSeconds,
              remaining <= options.countdownWindowSeconds else { return nil }

        if status.autoMuteHolding {
            // Parked because the mic can't be heard: the countdown isn't moving.
            return Countdown(fraction: 1, label: "Auto-mute active \u{2022} no mic", value: "Paused", color: amber)
        }
        // Measure against the window (or the timeout, if that's shorter), so
        // the fill starts full and the colors turn at the same points whatever
        // the settings.
        let span = max(1, min(options.countdownWindowSeconds, status.autoMuteTimeoutSeconds))
        let fraction = min(max(CGFloat(remaining) / CGFloat(span), 0), 1)
        let color = fraction > 0.5 ? green : (fraction > 0.2 ? amber : red)
        return Countdown(fraction: fraction, label: "Auto-mute active", value: format(remaining), color: color)
    }

    static func render(status: Status, options: NeoPanelOptions = NeoPanelOptions(), at date: Date = Date()) -> Data {
        PixelCanvas.renderPNG(width: Int(width), height: Int(height)) {
            background.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            if let countdown = countdown(status: status, options: options) {
                drawCountdown(countdown, style: options.countdownStyle)
                return
            }

            let centerX = width / 2
            PixelCanvas.drawCenteredText(timeFormatter(use24Hour: options.use24Hour).string(from: date),
                                         centerX: centerX, y: 16, size: 30, weight: .bold, color: primaryText)
            PixelCanvas.drawCenteredText(dateFormatter.string(from: date), centerX: centerX, y: 4, size: 13, weight: .regular, color: secondaryText)

            if status.inCall {
                if options.showMic {
                    drawBadge(symbol: status.micEnabled ? "mic.fill" : "mic.slash.fill",
                              color: status.micEnabled ? green : red,
                              diameter: 44, center: NSPoint(x: 25, y: 25))
                }
                if options.showCamera {
                    drawBadge(symbol: status.cameraEnabled ? "video.fill" : "video.slash.fill",
                              color: status.cameraEnabled ? green : red,
                              diameter: 44, center: NSPoint(x: 207, y: 25))
                }
            }
        }
    }

    private static func drawCountdown(_ countdown: Countdown, style: NeoPanelOptions.CountdownStyle) {
        let filled = NSRect(x: 0, y: 0, width: (width * countdown.fraction).rounded(), height: height)
        switch style {
        case .fill:
            drawCountdownText(countdown, labelColor: primaryText, valueColor: primaryText)
            countdown.color.setFill()
            filled.fill()
            // The same text again in dark, but only where the fill is, so each
            // letter flips as the fill drains past it.
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: filled).addClip()
            drawCountdownText(countdown, labelColor: onFillText, valueColor: onFillText)
            NSGraphicsContext.restoreGraphicsState()
        case .tint:
            countdown.color.withAlphaComponent(0.25).setFill()
            filled.fill()
            drawCountdownText(countdown, labelColor: countdown.color, valueColor: countdown.color)
        }
    }

    private static func drawCountdownText(_ countdown: Countdown, labelColor: NSColor, valueColor: NSColor) {
        let centerX = width / 2
        PixelCanvas.drawCenteredText(countdown.label, centerX: centerX, y: 35, size: 11, weight: .semibold, color: labelColor)
        PixelCanvas.drawCenteredText(countdown.value, centerX: centerX, y: 2, size: 31, weight: .bold, color: valueColor, monospacedDigits: true)
    }

    private static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func drawBadge(symbol: String, color: NSColor, diameter: CGFloat, center: NSPoint) {
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: rect).fill()
        PixelCanvas.drawSymbol(symbol, center: center, pointSize: diameter * 0.46, weight: .semibold, color: color)
    }
}
