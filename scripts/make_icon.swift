import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the app icon: a microphone in an ember ring, with a sound wave, on warm paper.
// Usage: swift scripts/make_icon.swift <output.png> [--rounded]
// App Store icons must be opaque and square. The macOS icon gets its own rounded shape.

let arguments = CommandLine.arguments
let output = URL(fileURLWithPath: arguments[1])
let rounded = arguments.contains("--rounded")
let size = 1024
let side = CGFloat(size)

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let alpha: CGImageAlphaInfo = rounded ? .premultipliedLast : .noneSkipLast
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
    bitmapInfo: alpha.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let ink = color(0.11, 0.106, 0.098)
let ember = color(0.91, 0.455, 0.231)

if rounded {
    // macOS icon grid: 824pt shape centred in the 1024pt canvas.
    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil))
    context.clip()
}

// Background: warm paper.
let background = CGGradient(
    colorsSpace: space,
    colors: [color(0.985, 0.978, 0.958), color(0.925, 0.912, 0.878)] as CFArray,
    locations: [0, 1])!
context.drawLinearGradient(
    background, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])

// Everything below is drawn on a 1024 grid, scaled down to fit the macOS shape.
if rounded {
    context.translateBy(x: side / 2, y: side / 2)
    context.scaleBy(x: 0.8, y: 0.8)
    context.translateBy(x: -side / 2, y: -side / 2)
}

let ringCentre = CGPoint(x: 322, y: 512)
let ringRadius: CGFloat = 222

// The white disc, with a soft shadow.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0, 0, 0, 0.2))
context.setFillColor(color(1, 1, 1))
context.addArc(center: ringCentre, radius: ringRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.fillPath()
context.restoreGState()

// The ember ring.
context.setStrokeColor(ember)
context.setLineWidth(34)
context.addArc(center: ringCentre, radius: ringRadius - 17, startAngle: 0, endAngle: .pi * 2, clockwise: false)
context.strokePath()

// The microphone.
context.setStrokeColor(ink)
context.setLineWidth(30)
context.setLineCap(.round)
let capsule = CGRect(x: ringCentre.x - 50, y: ringCentre.y - 28, width: 100, height: 168)
context.addPath(CGPath(roundedRect: capsule, cornerWidth: 50, cornerHeight: 50, transform: nil))
context.strokePath()
let cradleCentre = CGPoint(x: ringCentre.x, y: ringCentre.y + 16)
context.addArc(center: cradleCentre, radius: 92, startAngle: 0, endAngle: .pi, clockwise: true)
context.strokePath()
context.move(to: CGPoint(x: ringCentre.x, y: cradleCentre.y - 92))
context.addLine(to: CGPoint(x: ringCentre.x, y: cradleCentre.y - 148))
context.strokePath()

// The sound wave. Few, thick bars so it still reads at Dock size.
let heights: [CGFloat] = [250, 500, 340, 190]
let barWidth: CGFloat = 60
let gap: CGFloat = 36
for (index, height) in heights.enumerated() {
    let x = 588 + CGFloat(index) * (barWidth + gap)
    let rect = CGRect(x: x, y: 512 - height / 2, width: barWidth, height: height)
    context.setFillColor(index == 2 ? ember : ink)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    context.fillPath()
}

let image = context.makeImage()!
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path)")
