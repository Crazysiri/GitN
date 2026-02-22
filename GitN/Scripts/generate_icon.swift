#!/usr/bin/env swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("No graphics context")
}

// --- Background: rounded superellipse ---
let inset: CGFloat = 20
let cornerRadius: CGFloat = size * 0.22
let bgRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Gradient: deep indigo → teal
let colors = [
    NSColor(calibratedRed: 0.12, green: 0.11, blue: 0.28, alpha: 1.0).cgColor,
    NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.35, alpha: 1.0).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
ctx.saveGState()
bgPath.addClip()
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: size / 2, y: size - inset),
                       end: CGPoint(x: size / 2, y: inset),
                       options: [])
ctx.restoreGState()

// Subtle inner glow
ctx.saveGState()
bgPath.addClip()
let glowColor = NSColor(white: 1.0, alpha: 0.04).cgColor
ctx.setFillColor(glowColor)
let glowRect = CGRect(x: size * 0.1, y: size * 0.5, width: size * 0.8, height: size * 0.5)
ctx.fillEllipse(in: glowRect)
ctx.restoreGState()

// --- Git branch graphic (behind the N) ---
let branchColor = NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.75, alpha: 0.25)
ctx.saveGState()
bgPath.addClip()

func drawBranch() {
    let path = NSBezierPath()
    path.lineWidth = 12
    branchColor.setStroke()

    // Main branch line (vertical, slightly left of center)
    path.move(to: NSPoint(x: size * 0.38, y: size * 0.15))
    path.line(to: NSPoint(x: size * 0.38, y: size * 0.85))
    path.stroke()

    // Branch-off line
    let branch = NSBezierPath()
    branch.lineWidth = 10
    branchColor.setStroke()
    branch.move(to: NSPoint(x: size * 0.38, y: size * 0.55))
    branch.curve(to: NSPoint(x: size * 0.65, y: size * 0.78),
                 controlPoint1: NSPoint(x: size * 0.45, y: size * 0.62),
                 controlPoint2: NSPoint(x: size * 0.55, y: size * 0.75))
    branch.stroke()

    // Node dots
    let dotRadius: CGFloat = 14
    let dotColor = NSColor(calibratedRed: 0.3, green: 0.85, blue: 0.75, alpha: 0.35)
    dotColor.setFill()
    let dots = [
        NSPoint(x: size * 0.38, y: size * 0.35),
        NSPoint(x: size * 0.38, y: size * 0.55),
        NSPoint(x: size * 0.65, y: size * 0.78),
    ]
    for dot in dots {
        let r = CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius,
                        width: dotRadius * 2, height: dotRadius * 2)
        NSBezierPath(ovalIn: r).fill()
    }
}
drawBranch()
ctx.restoreGState()

// --- Letter "N" ---
ctx.saveGState()
bgPath.addClip()

let font = NSFont.systemFont(ofSize: size * 0.52, weight: .bold)
let paragraphStyle = NSMutableParagraphStyle()
paragraphStyle.alignment = .center

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraphStyle,
]
let str = NSAttributedString(string: "N", attributes: attrs)
let textSize = str.size()
let textRect = CGRect(
    x: (size - textSize.width) / 2,
    y: (size - textSize.height) / 2 - size * 0.02,
    width: textSize.width,
    height: textSize.height
)
str.draw(in: textRect)
ctx.restoreGState()

// --- Small accent: git dots on the N's diagonal ---
ctx.saveGState()
bgPath.addClip()
let accentColor = NSColor(calibratedRed: 0.35, green: 0.9, blue: 0.8, alpha: 1.0)
accentColor.setFill()
let accentDots = [
    NSPoint(x: size * 0.52, y: size * 0.42),
    NSPoint(x: size * 0.52, y: size * 0.52),
    NSPoint(x: size * 0.52, y: size * 0.62),
]
for dot in accentDots {
    let r: CGFloat = 7
    NSBezierPath(ovalIn: CGRect(x: dot.x - r, y: dot.y - r, width: r * 2, height: r * 2)).fill()
}
ctx.restoreGState()

image.unlockFocus()

// --- Save as PNG ---
guard let tiffData = image.tiffRepresentation,
      let bitmapRep = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapRep.representation(using: .png, properties: [:])
else {
    fatalError("Failed to create PNG")
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon_1024.png"
try! pngData.write(to: URL(fileURLWithPath: outputPath))
print("Icon saved to \(outputPath)")
