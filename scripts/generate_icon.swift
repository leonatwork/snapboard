import AppKit
import CoreGraphics

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let context = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Corner radius for modern macOS squircle style
    let cornerRadius = size * 0.224
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.05, dy: size * 0.05), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    context.saveGState()
    context.addPath(path)
    context.clip()

    // Background Gradient (Deep indigo to vibrant cyan/blue)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let colors = [
        NSColor(red: 0.12, green: 0.16, blue: 0.35, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.55, blue: 0.95, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // Subtle inner glow / border
    context.restoreGState()
    context.saveGState()
    context.addPath(path)
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.25).cgColor)
    context.setLineWidth(size * 0.02)
    context.strokePath()
    context.restoreGState()

    // Draw Camera / Viewfinder Symbol in center
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolRect = CGRect(
            x: (size - size * 0.55) / 2,
            y: (size - size * 0.55) / 2,
            width: size * 0.55,
            height: size * 0.55
        )
        // Tint symbol white with subtle drop shadow
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.03), blur: size * 0.05, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        context.restoreGState()
    }

    image.unlockFocus()
    return image
}

let fileManager = FileManager.default
let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in sizes {
    let img = createIcon(size: size)
    if let tiffData = img.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiffData),
       let pngData = bitmap.representation(using: .png, properties: [:]) {
        let fileURL = iconsetDir.appendingPathComponent(name)
        try? pngData.write(to: fileURL)
    }
}

print("Iconset generated successfully.")
