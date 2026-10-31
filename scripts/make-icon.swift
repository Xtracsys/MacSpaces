// swift scripts/make-icon.swift <output-dir>
// Draws the MacSpaces icon (usage ring on a gradient rounded square)
// and writes AppIcon.icns into the given directory.
import AppKit
import CoreGraphics

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "."

func drawIcon(size: CGFloat) -> CGImage? {
    let side = size
    guard let ctx = CGContext(
        data: nil, width: Int(side), height: Int(side),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let inset = side * 0.08
    let rect = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let radius = side * 0.22

    // Rounded-square gradient background
    let colors = [
        CGColor(srgbRed: 0.22, green: 0.30, blue: 0.85, alpha: 1),
        CGColor(srgbRed: 0.10, green: 0.62, blue: 0.72, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
    ctx.saveGState()
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    // Usage ring
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = side * 0.26
    let lineWidth = side * 0.075
    ctx.setLineWidth(lineWidth)
    ctx.setLineCap(.round)

    // Track
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.25))
    ctx.addArc(center: center, radius: ringRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()

    // Used arc (72%)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: center, radius: ringRadius, startAngle: .pi / 2, endAngle: .pi / 2 + 2 * .pi * 0.72, clockwise: false)
    ctx.strokePath()

    // Bar chart glyphs at the bottom
    let barColor = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9)
    ctx.setFillColor(barColor)
    let barWidth = side * 0.055
    let gap = side * 0.04
    let baseY = rect.minY + side * 0.16
    let heights: [CGFloat] = [0.10, 0.16, 0.08, 0.20]
    var x = center.x - (barWidth * 2 + gap * 1.5)
    for h in heights {
        ctx.fill(CGRect(x: x, y: baseY, width: barWidth, height: side * h))
        x += barWidth + gap
    }

    return ctx.makeImage()
}

var sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]
let iconsetDir = (outputDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for size in sizes {
    guard let image = drawIcon(size: CGFloat(size)) else {
        fputs("Failed to draw icon at \(size)\n", stderr)
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode PNG at \(size)\n", stderr)
        exit(1)
    }
    let filenames: [String]
    switch size {
    case 16: filenames = ["icon_16x16.png"]
    case 32: filenames = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: filenames = ["icon_32x32@2x.png"]
    case 128: filenames = ["icon_128x128.png"]
    case 256: filenames = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: filenames = ["icon_256x256@2x.png", "icon_512x512.png"]
    case 1024: filenames = ["icon_512x512@2x.png"]
    default: filenames = []
    }
    for filename in filenames {
        let url = URL(fileURLWithPath: iconsetDir).appendingPathComponent(filename)
        try! png.write(to: url)
    }
}

// iconutil → icns
let icnsURL = URL(fileURLWithPath: (outputDir as NSString).appendingPathComponent("AppIcon.icns"))
try? FileManager.default.removeItem(at: icnsURL)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", icnsURL.path]
try? proc.run()
proc.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconsetDir)

if FileManager.default.fileExists(atPath: icnsURL.path) {
    print("Wrote \(icnsURL.path)")
} else {
    exit(1)
}
