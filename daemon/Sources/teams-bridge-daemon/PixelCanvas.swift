import AppKit
import Foundation

/// Draws into an explicit pixel-sized bitmap context (not
/// `NSImage.lockFocus`, which renders at the host display's Retina backing
/// scale — a 232x50 canvas would silently come out 464x100, and Stream Deck
/// wants exact sizes). 1 point == 1 pixel.
enum PixelCanvas {
    static func renderPNG(width: Int, height: Int, draw: () -> Void) -> Data {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return Data() }
        rep.size = NSSize(width: width, height: height)

        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        draw()
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    static func drawCenteredText(
        _ text: String, centerX: CGFloat, y: CGFloat, size: CGFloat,
        weight: NSFont.Weight, color: NSColor, monospacedDigits: Bool = false
    ) {
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        let attrString = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        attrString.draw(at: NSPoint(x: centerX - attrString.size().width / 2, y: y))
    }

    static func drawSymbol(_ name: String, center: NSPoint, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
              let glyph = base.withSymbolConfiguration(config) else { return }
        let size = glyph.size
        glyph.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
                   from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
