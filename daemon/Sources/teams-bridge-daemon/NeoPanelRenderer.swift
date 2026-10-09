import AppKit
import Foundation

/// Renders the Stream Deck Neo info-strip panel (232x50) as a single
/// composited PNG: date/time in the system font (SF Pro — that's just what
/// NSFont.systemFont already is) plus SF Symbol status badges for
/// mic/camera. The Neo action in the Stream Deck plugin fetches this on a
/// timer (for the clock) and whenever status changes.
enum NeoPanelRenderer {
    static let width: CGFloat = 232
    static let height: CGFloat = 50

    private static let background = NSColor(calibratedWhite: 0.07, alpha: 1)
    private static let primaryText = NSColor(calibratedWhite: 0.95, alpha: 1)
    private static let secondaryText = NSColor(calibratedWhite: 0.65, alpha: 1)
    private static let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    private static let red = NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    static func render(status: Status, at date: Date = Date()) -> Data {
        PixelCanvas.renderPNG(width: Int(width), height: Int(height)) {
            background.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            let centerX = width / 2
            PixelCanvas.drawCenteredText(timeFormatter.string(from: date), centerX: centerX, y: 16, size: 30, weight: .bold, color: primaryText)
            PixelCanvas.drawCenteredText(dateFormatter.string(from: date), centerX: centerX, y: 4, size: 13, weight: .regular, color: secondaryText)

            if status.inCall {
                drawBadge(symbol: status.micEnabled ? "mic.fill" : "mic.slash.fill",
                          color: status.micEnabled ? green : red,
                          diameter: 44, center: NSPoint(x: 25, y: 25))
                drawBadge(symbol: status.cameraEnabled ? "video.fill" : "video.slash.fill",
                          color: status.cameraEnabled ? green : red,
                          diameter: 44, center: NSPoint(x: 207, y: 25))
            }
        }
    }

    private static func drawBadge(symbol: String, color: NSColor, diameter: CGFloat, center: NSPoint) {
        let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: rect).fill()
        PixelCanvas.drawSymbol(symbol, center: center, pointSize: diameter * 0.46, weight: .semibold, color: color)
    }
}
