import AppKit
import Foundation

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let margin = size * 0.1
    let iconRect = rect.insetBy(dx: margin, dy: margin)
    let cornerRadius = iconRect.width * 0.225

    // Outer rounded rectangle path (Squircle shape)
    let path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()

    // Background Gradient (Dark Navy / Slate)
    let colors = [
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.03, green: 0.04, blue: 0.08, alpha: 1.0).cgColor
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        context.drawLinearGradient(gradient, start: CGPoint(x: iconRect.midX, y: iconRect.maxY), end: CGPoint(x: iconRect.midX, y: iconRect.minY), options: [])
    }

    // Subtle background grid or glow
    let center = CGPoint(x: iconRect.midX, y: iconRect.midY)

    // Draw Sunburst rings
    let sliceColors: [NSColor] = [
        NSColor(calibratedRed: 0.23, green: 0.51, blue: 0.96, alpha: 0.9), // Blue
        NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 0.9), // Purple
        NSColor(calibratedRed: 0.93, green: 0.28, blue: 0.60, alpha: 0.9), // Pink
        NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.18, alpha: 0.9), // Orange
        NSColor(calibratedRed: 0.13, green: 0.77, blue: 0.64, alpha: 0.9), // Teal
        NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 0.9)  // Green
    ]

    // Inner ring slices
    let rInner1 = size * 0.16
    let rOuter1 = size * 0.26
    let angles1: [(CGFloat, CGFloat, NSColor)] = [
        (0.0, .pi * 0.6, sliceColors[0]),
        (.pi * 0.62, .pi * 1.1, sliceColors[1]),
        (.pi * 1.12, .pi * 1.65, sliceColors[2]),
        (.pi * 1.67, .pi * 1.98, sliceColors[3])
    ]

    for (startA, endA, color) in angles1 {
        context.beginPath()
        context.addArc(center: center, radius: rOuter1, startAngle: startA, endAngle: endA, clockwise: false)
        context.addArc(center: center, radius: rInner1, startAngle: endA, endAngle: startA, clockwise: true)
        context.closePath()
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    // Outer ring slices
    let rInner2 = size * 0.275
    let rOuter2 = size * 0.36
    let angles2: [(CGFloat, CGFloat, NSColor)] = [
        (0.0, .pi * 0.35, sliceColors[0].blended(withFraction: 0.2, of: .white)!),
        (.pi * 0.37, .pi * 0.58, sliceColors[4]),
        (.pi * 0.63, .pi * 0.9, sliceColors[1].blended(withFraction: 0.2, of: .white)!),
        (.pi * 0.92, .pi * 1.08, sliceColors[5]),
        (.pi * 1.14, .pi * 1.4, sliceColors[2].blended(withFraction: 0.2, of: .white)!),
        (.pi * 1.42, .pi * 1.63, sliceColors[4]),
        (.pi * 1.69, .pi * 1.96, sliceColors[3].blended(withFraction: 0.2, of: .white)!)
    ]

    for (startA, endA, color) in angles2 {
        context.beginPath()
        context.addArc(center: center, radius: rOuter2, startAngle: startA, endAngle: endA, clockwise: false)
        context.addArc(center: center, radius: rInner2, startAngle: endA, endAngle: startA, clockwise: true)
        context.closePath()
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    // Central disk circle
    let centerDiskRadius = size * 0.12
    context.beginPath()
    context.addArc(center: center, radius: centerDiskRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.setFillColor(NSColor(calibratedRed: 0.12, green: 0.15, blue: 0.24, alpha: 1.0).cgColor)
    context.fillPath()

    context.beginPath()
    context.addArc(center: center, radius: centerDiskRadius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.setLineWidth(size * 0.015)
    context.setStrokeColor(NSColor(calibratedRed: 0.4, green: 0.6, blue: 1.0, alpha: 0.8).cgColor)
    context.strokePath()

    // Central pie chart symbol
    context.beginPath()
    context.move(to: center)
    context.addArc(center: center, radius: centerDiskRadius * 0.65, startAngle: -.pi * 0.2, endAngle: .pi * 1.2, clockwise: false)
    context.closePath()
    context.setFillColor(NSColor(calibratedRed: 0.3, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
    context.fillPath()

    context.restoreGState()

    // Outer border shine
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(size * 0.02)
    context.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    context.strokePath()
    context.restoreGState()

    image.unlockFocus()
    return image
}

func savePNG(image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return
    }
    try? pngData.write(to: url)
}

let fileManager = FileManager.default
let iconsetURL = URL(fileURLWithPath: "Packaging/AppIcon.iconset")
try? fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    let destination = iconsetURL.appendingPathComponent(name)
    savePNG(image: img, to: destination)
}

print("Iconset generated successfully at Packaging/AppIcon.iconset")
