import AppKit
import Foundation

/// Renders the auto-mute keys that need to show live state (a countdown
/// ring) — too dynamic for the static per-state images in the manifest. The
/// Stream Deck plugin fetches these and sets them as the key image.
enum KeyRenderer {
    static let size = 144

    private static let background = NSColor(calibratedWhite: 0.12, alpha: 1)
    private static let track = NSColor(calibratedWhite: 0.27, alpha: 1)
    private static let primaryText = NSColor(calibratedWhite: 0.97, alpha: 1)
    private static let dimText = NSColor(calibratedWhite: 0.52, alpha: 1)
    private static let accent = NSColor(calibratedRed: 0.25, green: 0.55, blue: 1.00, alpha: 1)
    private static let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    private static let amber = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.10, alpha: 1)
    private static let red = NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)

    // MARK: - Timeout key

    /// A preset timeout. Idle presets show their value; the selected one
    /// shows a ring that drains as the auto-mute countdown runs down.
    static func timeoutKey(seconds: Int, status: Status) -> Data {
        let selected = status.autoMuteTimeoutSeconds == seconds
        let counting = selected && status.autoMuteRemainingSeconds != nil
        let center = NSPoint(x: 72, y: 76)

        return PixelCanvas.renderPNG(width: size, height: size) {
            drawBackground()

            if counting, let remaining = status.autoMuteRemainingSeconds {
                // Bonus time can push remaining past the base timeout; the
                // ring just stays full until it drains below it.
                let total = max(status.autoMuteTimeoutSeconds, remaining)
                let fraction = Double(remaining) / Double(max(total, 1))
                if status.autoMuteHolding {
                    // Can't hear the mic, so the countdown is parked: say so
                    // rather than show a ring that never moves.
                    strokeRing(center: center, fraction: 1, color: amber.withAlphaComponent(0.55))
                    drawValue(format(remaining), center: center, color: primaryText, unitText: "no mic", unitColor: amber)
                } else {
                    strokeRing(center: center, fraction: 1, color: track)
                    strokeRing(center: center, fraction: fraction, color: countdownColor(fraction))
                    drawValue(format(remaining), center: center, color: primaryText)
                }
            } else if selected {
                strokeRing(center: center, fraction: 1, color: status.autoMuteEnabled ? accent : track)
                drawValue(format(seconds), center: center, color: status.autoMuteEnabled ? primaryText : dimText)
            } else {
                strokeRing(center: center, fraction: 1, color: NSColor(calibratedWhite: 0.20, alpha: 1))
                drawValue(format(seconds), center: center, color: dimText)
            }
        }
    }

    // MARK: - Add-time key

    /// Microwave-style "+N seconds". Lit while there's a countdown to extend.
    static func addTimeKey(seconds: Int, status: Status) -> Data {
        let active = status.autoMuteRemainingSeconds != nil
        let color = active ? amber : dimText

        return PixelCanvas.renderPNG(width: size, height: size) {
            drawBackground()
            PixelCanvas.drawSymbol("timer", center: NSPoint(x: 72, y: 112), pointSize: 24, weight: .semibold, color: color)

            let text = "+" + format(seconds)
            PixelCanvas.drawCenteredText(text, centerX: 72, y: 50, size: valueFontSize(text),
                                         weight: .bold, color: active ? primaryText : dimText, monospacedDigits: true)
            PixelCanvas.drawCenteredText(unit(for: seconds), centerX: 72, y: 24, size: 17,
                                         weight: .medium, color: color)
        }
    }

    // MARK: - Pieces

    private static func drawBackground() {
        background.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: 28, yRadius: 28).fill()
    }

    private static func drawValue(_ text: String, center: NSPoint, color: NSColor, unitText: String? = nil, unitColor: NSColor? = nil) {
        let fontSize = valueFontSize(text)
        PixelCanvas.drawCenteredText(text, centerX: center.x, y: center.y - fontSize * 0.42, size: fontSize,
                                     weight: .bold, color: color, monospacedDigits: true)
        PixelCanvas.drawCenteredText(unitText ?? unit(forDisplayed: text), centerX: center.x, y: center.y - 36, size: 14,
                                     weight: .medium, color: unitColor ?? dimText)
    }

    /// Strokes a ring that starts at 12 o'clock and runs clockwise.
    private static func strokeRing(center: NSPoint, fraction: Double, color: NSColor) {
        guard fraction > 0 else { return }
        let path = NSBezierPath()
        if fraction >= 1 {
            path.appendOval(in: NSRect(x: center.x - 54, y: center.y - 54, width: 108, height: 108))
        } else {
            path.appendArc(withCenter: center, radius: 54, startAngle: 90, endAngle: 90 - 360 * fraction, clockwise: true)
        }
        path.lineWidth = 9
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }

    private static func countdownColor(_ fraction: Double) -> NSColor {
        fraction > 0.5 ? green : (fraction > 0.2 ? amber : red)
    }

    // MARK: - Formatting

    /// Whole seconds below 100, then m:ss, so long timeouts still fit.
    private static func format(_ seconds: Int) -> String {
        seconds < 100 ? "\(seconds)" : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func unit(for seconds: Int) -> String { seconds < 100 ? "sec" : "min" }
    private static func unit(forDisplayed text: String) -> String { text.contains(":") ? "min" : "sec" }

    private static func valueFontSize(_ text: String) -> CGFloat {
        switch text.count {
        case ...3: return 44
        case 4: return 36
        default: return 30
        }
    }
}
