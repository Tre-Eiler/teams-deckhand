// Renders Stream Deck plugin icons from Apple's SF Symbols, using the
// officially supported NSImage(systemSymbolName:) rendering API (never
// extracts/traces the raw glyph artwork — this only asks AppKit to draw a
// symbol it already ships, same as any Mac app would).
//
// Usage: swiftc render-icons.swift -o render-icons && ./render-icons <sdPluginDir> [AppIcon.iconset]
// With the optional second argument it also writes the macOS app icon set
// (turn it into AppIcon.icns with `iconutil -c icns`).

import AppKit
import Foundation

/// Draws into an explicit pixel-sized bitmap context (not `NSImage.lockFocus`,
/// which silently renders at the host display's Retina backing scale —
/// asking for a 72x72 canvas on this Mac produced a 144x144 PNG).
func renderPixels(width: Int, height: Int, draw: (CGFloat, CGFloat) -> Void) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap rep")
    }
    rep.size = NSSize(width: width, height: height) // 1 point == 1 pixel

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("Failed to create graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(CGFloat(width), CGFloat(height))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG conversion failed")
    }
    return png
}

func renderSymbol(
    name: String,
    canvas: CGFloat,
    pointSize: CGFloat,
    weight: NSFont.Weight = .regular,
    tint: NSColor,
    background: NSColor? = nil,
    backgroundCornerRadius: CGFloat = 0
) -> Data {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
        fatalError("Missing SF Symbol: \(name) (is this machine's macOS new enough to have it?)")
    }
    guard let symbol = base.withSymbolConfiguration(config) else {
        fatalError("Failed to configure SF Symbol: \(name)")
    }

    return renderPixels(width: Int(canvas), height: Int(canvas)) { w, h in
        if let background {
            let rect = NSRect(x: 0, y: 0, width: w, height: h)
            let path = backgroundCornerRadius > 0
                ? NSBezierPath(roundedRect: rect, xRadius: backgroundCornerRadius, yRadius: backgroundCornerRadius)
                : NSBezierPath(rect: rect)
            background.setFill()
            path.fill()
        }

        let symSize = symbol.size
        let origin = NSPoint(x: (w - symSize.width) / 2, y: (h - symSize.height) / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}

func write(_ data: Data, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

// MARK: - Palette

let white = NSColor.white
let green = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1) // systemGreen-ish
let red = NSColor(calibratedRed: 1.00, green: 0.23, blue: 0.19, alpha: 1) // systemRed-ish
let amber = NSColor(calibratedRed: 0.85, green: 0.62, blue: 0.02, alpha: 1)
let gray = NSColor(calibratedRed: 0.56, green: 0.56, blue: 0.58, alpha: 1)
let brandBlue = NSColor(calibratedRed: 0.18, green: 0.40, blue: 0.71, alpha: 1)
let charcoal = NSColor(calibratedWhite: 0.12, alpha: 1)
let amberBright = NSColor(calibratedRed: 1.00, green: 0.72, blue: 0.10, alpha: 1)

// MARK: - Args

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("Usage: ./render-icons <sdPluginDir>")
    exit(1)
}
let root = args[1]

struct KeyIcon {
    let action: String
    let symbolOn: String
    let symbolOff: String
    let bgOn: NSColor
    let bgOff: NSColor
    let tintOn: NSColor
    let tintOff: NSColor
}

let keyIcons: [KeyIcon] = [
    KeyIcon(action: "mic", symbolOn: "mic.fill", symbolOff: "mic.slash.fill", bgOn: green, bgOff: red, tintOn: white, tintOff: white),
    KeyIcon(action: "camera", symbolOn: "video.fill", symbolOff: "video.slash.fill", bgOn: green, bgOff: red, tintOn: white, tintOff: white),
    KeyIcon(action: "hand", symbolOn: "hand.raised.fill", symbolOff: "hand.raised", bgOn: amber, bgOff: gray, tintOn: white, tintOff: white),
    KeyIcon(action: "hangup", symbolOn: "phone.down.fill", symbolOff: "phone.down", bgOn: red, bgOff: gray, tintOn: white, tintOff: white),
    KeyIcon(action: "automute", symbolOn: "waveform", symbolOff: "waveform.slash", bgOn: green, bgOff: gray, tintOn: white, tintOff: white),
]

for icon in keyIcons {
    let actionListSymbol = icon.symbolOn // action-list icon just shows the "on" glyph, monochrome
    write(renderSymbol(name: actionListSymbol, canvas: 20, pointSize: 13, weight: .medium, tint: white),
          to: "\(root)/imgs/actions/\(icon.action)/icon.png")
    write(renderSymbol(name: actionListSymbol, canvas: 40, pointSize: 26, weight: .medium, tint: white),
          to: "\(root)/imgs/actions/\(icon.action)/icon@2x.png")

    write(renderSymbol(name: icon.symbolOff, canvas: 72, pointSize: 32, weight: .semibold, tint: icon.tintOff, background: icon.bgOff, backgroundCornerRadius: 14),
          to: "\(root)/imgs/actions/\(icon.action)/key-off.png")
    write(renderSymbol(name: icon.symbolOff, canvas: 144, pointSize: 64, weight: .semibold, tint: icon.tintOff, background: icon.bgOff, backgroundCornerRadius: 28),
          to: "\(root)/imgs/actions/\(icon.action)/key-off@2x.png")

    write(renderSymbol(name: icon.symbolOn, canvas: 72, pointSize: 32, weight: .semibold, tint: icon.tintOn, background: icon.bgOn, backgroundCornerRadius: 14),
          to: "\(root)/imgs/actions/\(icon.action)/key-on.png")
    write(renderSymbol(name: icon.symbolOn, canvas: 144, pointSize: 64, weight: .semibold, tint: icon.tintOn, background: icon.bgOn, backgroundCornerRadius: 28),
          to: "\(root)/imgs/actions/\(icon.action)/key-on@2x.png")
}

// Neo status panel: action-list icon, plus a State image the manifest schema
// requires even though Neo (an infobar, not a key) never actually shows it.
write(renderSymbol(name: "clock.fill", canvas: 20, pointSize: 13, weight: .medium, tint: white),
      to: "\(root)/imgs/actions/neo-status/icon.png")
write(renderSymbol(name: "clock.fill", canvas: 40, pointSize: 26, weight: .medium, tint: white),
      to: "\(root)/imgs/actions/neo-status/icon@2x.png")
write(renderSymbol(name: "clock.fill", canvas: 72, pointSize: 32, weight: .semibold, tint: white, background: brandBlue, backgroundCornerRadius: 14),
      to: "\(root)/imgs/actions/neo-status/key.png")
write(renderSymbol(name: "clock.fill", canvas: 144, pointSize: 64, weight: .semibold, tint: white, background: brandBlue, backgroundCornerRadius: 28),
      to: "\(root)/imgs/actions/neo-status/key@2x.png")

// Auto-mute timeout / add-time keys: their faces are drawn live by the daemon
// (countdown ring, "+30"); these static images are the action-list icon and
// the fallback face shown when the daemon isn't reachable.
for (action, symbol, tint) in [("automute-timeout", "timer", white), ("automute-add", "plus.circle.fill", amberBright)] {
    write(renderSymbol(name: symbol, canvas: 20, pointSize: 13, weight: .medium, tint: white),
          to: "\(root)/imgs/actions/\(action)/icon.png")
    write(renderSymbol(name: symbol, canvas: 40, pointSize: 26, weight: .medium, tint: white),
          to: "\(root)/imgs/actions/\(action)/icon@2x.png")
    write(renderSymbol(name: symbol, canvas: 72, pointSize: 32, weight: .semibold, tint: tint, background: charcoal, backgroundCornerRadius: 14),
          to: "\(root)/imgs/actions/\(action)/key.png")
    write(renderSymbol(name: symbol, canvas: 144, pointSize: 64, weight: .semibold, tint: tint, background: charcoal, backgroundCornerRadius: 28),
          to: "\(root)/imgs/actions/\(action)/key@2x.png")
}

// Plugin category icon (28x28/56x56), white monochrome, transparent.
write(renderSymbol(name: "bubble.left.and.bubble.right.fill", canvas: 28, pointSize: 17, weight: .medium, tint: white),
      to: "\(root)/imgs/plugin/category-icon.png")
write(renderSymbol(name: "bubble.left.and.bubble.right.fill", canvas: 56, pointSize: 34, weight: .medium, tint: white),
      to: "\(root)/imgs/plugin/category-icon@2x.png")

// Plugin marketplace/preferences icon (256x256/512x512) — full color, on brand.
write(renderSymbol(name: "bubble.left.and.bubble.right.fill", canvas: 256, pointSize: 120, weight: .medium, tint: white, background: brandBlue, backgroundCornerRadius: 56),
      to: "\(root)/imgs/plugin/marketplace.png")
write(renderSymbol(name: "bubble.left.and.bubble.right.fill", canvas: 512, pointSize: 240, weight: .medium, tint: white, background: brandBlue, backgroundCornerRadius: 112),
      to: "\(root)/imgs/plugin/marketplace@2x.png")

// macOS app icon set. App icons carry their own margin: the squircle fills
// ~80% of the canvas, centered, like the system's icon grid.
if args.count >= 3 {
    let iconset = args[2]
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = base * scale
            let inset = CGFloat(px) * 0.10
            let body = CGFloat(px) - inset * 2
            let png = renderPixels(width: px, height: px) { w, h in
                let rect = NSRect(x: inset, y: inset, width: body, height: body)
                let squircle = NSBezierPath(roundedRect: rect, xRadius: body * 0.225, yRadius: body * 0.225)
                NSGradient(starting: NSColor(calibratedRed: 0.28, green: 0.52, blue: 0.86, alpha: 1),
                           ending: NSColor(calibratedRed: 0.14, green: 0.32, blue: 0.62, alpha: 1))?
                    .draw(in: squircle, angle: -90)
                let config = NSImage.SymbolConfiguration(pointSize: body * 0.46, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [white]))
                if let glyph = NSImage(systemSymbolName: "bubble.left.and.bubble.right.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let g = glyph.size
                    glyph.draw(at: NSPoint(x: (w - g.width) / 2, y: (h - g.height) / 2),
                               from: .zero, operation: .sourceOver, fraction: 1.0)
                }
            }
            write(png, to: "\(iconset)/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png")
        }
    }
}

print("Icons rendered to \(root)")
