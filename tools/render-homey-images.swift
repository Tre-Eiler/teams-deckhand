// Draws the Homey app's store and device images from plain shapes (no SF
// Symbols or other third-party artwork, so the results are safe to commit).
//
// Usage: swiftc tools/render-homey-images.swift -o tools/render-homey-images
//        tools/render-homey-images homey-app

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let brand = CGColor(red: 0.176, green: 0.392, blue: 0.706, alpha: 1)       // #2D64B4
let deep = CGColor(red: 0.075, green: 0.157, blue: 0.294, alpha: 1)
let key = CGColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1)
let green = CGColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
let red = CGColor(red: 0.95, green: 0.27, blue: 0.27, alpha: 1)
let amber = CGColor(red: 1.0, green: 0.72, blue: 0.0, alpha: 1)
let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

func png(width: Int, height: Int, to path: String, draw: (CGContext, CGFloat, CGFloat) -> Void) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context") }
    draw(ctx, CGFloat(width), CGFloat(height))
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { fatalError("png") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(path)") }
}

func rounded(_ ctx: CGContext, _ rect: CGRect, _ radius: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

/// One Stream Deck-style key: a dark square with a simple state mark.
enum Mark { case dot(CGColor), ring(CGColor, CGFloat), bars(CGColor), slash(CGColor) }

func drawKey(_ ctx: CGContext, _ rect: CGRect, _ mark: Mark) {
    let s = rect.width
    rounded(ctx, rect, s * 0.2, key)
    let c = CGPoint(x: rect.midX, y: rect.midY)
    switch mark {
    case .dot(let color):
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: c.x - s * 0.2, y: c.y - s * 0.2, width: s * 0.4, height: s * 0.4))
    case .ring(let color, let fraction):
        ctx.setStrokeColor(color); ctx.setLineWidth(s * 0.1); ctx.setLineCap(.round)
        ctx.addArc(center: c, radius: s * 0.28, startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi * fraction, clockwise: true)
        ctx.strokePath()
    case .bars(let color):
        ctx.setFillColor(color)
        for (i, h) in [0.22, 0.4, 0.3].enumerated() {
            let bw = s * 0.12
            let x = c.x - s * 0.22 + CGFloat(i) * s * 0.2
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: c.y - s * h / 2, width: bw, height: s * h), cornerWidth: bw / 2, cornerHeight: bw / 2, transform: nil))
            ctx.fillPath()
        }
    case .slash(let color):
        ctx.setStrokeColor(color); ctx.setLineWidth(s * 0.1); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: c.x - s * 0.22, y: c.y - s * 0.22)); ctx.addLine(to: CGPoint(x: c.x + s * 0.22, y: c.y + s * 0.22))
        ctx.strokePath()
    }
}

func background(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [brand, deep] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
}

/// App store image: a 3x2 grid of keys.
func appImage(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    background(ctx, w, h)
    let cell = min(w / 5.2, h / 3.9), gap = cell * 0.14
    let gridW = cell * 3 + gap * 2, gridH = cell * 2 + gap
    let origin = CGPoint(x: (w - gridW) / 2, y: (h - gridH) / 2)
    let marks: [Mark] = [.dot(green), .dot(red), .ring(amber, 0.7), .bars(white), .slash(red), .ring(green, 0.35)]
    for (i, mark) in marks.enumerated() {
        let col = CGFloat(i % 3), row = CGFloat(1 - i / 3)
        drawKey(ctx, CGRect(x: origin.x + col * (cell + gap), y: origin.y + row * (cell + gap), width: cell, height: cell), mark)
    }
}

/// Device image: a single key on a rounded brand tile.
func deviceImage(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    rounded(ctx, CGRect(x: 0, y: 0, width: w, height: h), w * 0.22, brand)
    drawKey(ctx, CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6), .ring(green, 0.72))
}

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "homey-app"
for (name, w, h) in [("small", 250, 175), ("large", 500, 350), ("xlarge", 1000, 700)] {
    png(width: w, height: h, to: "\(root)/assets/images/\(name).png", draw: appImage)
}
for (name, s) in [("small", 75), ("large", 500), ("xlarge", 1000)] {
    png(width: s, height: s, to: "\(root)/drivers/teams-status/assets/images/\(name).png", draw: deviceImage)
}
print("Rendered Homey images into \(root)")
