// Screenshot harness for the README images.
//
// Compiled together with the app sources (without `AppDelegate.swift`) by
// `scripts/screenshots/render.sh` and run inside a temporary .app bundle so that the
// `.lproj` localizations are picked up. It never captures the screen: the editor shows
// a demo image drawn in `DemoContent.swift`, and all windows are rendered offscreen.
//
// Usage: <harness> --out <dir> [--suffix .de] [-AppleLanguages "(de)"]

import AppKit
import SwiftUI

// MARK: - Arguments

func argument(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let outputDirectory = URL(fileURLWithPath: argument("--out") ?? ".", isDirectory: true)
let fileSuffix = argument("--suffix") ?? ""
let debugDirectory = argument("--debug").map { URL(fileURLWithPath: $0, isDirectory: true) }
/// Renders only the named shot ("editor" or "settings").
let onlyShot = argument("--only")
/// Compares the editor preview of a text annotation with the exported image and writes
/// both crops to this directory.
let verifyTextDirectory = argument("--verify-text").map { URL(fileURLWithPath: $0, isDirectory: true) }

/// Pixels per point of the rendered windows.
let renderScale: CGFloat = 2
/// Maximum width of the final PNGs in pixels.
let maxOutputWidth: CGFloat = 1600
/// Space around the window in points.
let margin: CGFloat = 28

// MARK: - Rendering helpers

/// A window that draws itself as the active (key and main) window without ever being
/// ordered on screen, so the title bar and prominent buttons render in their active colors.
final class ActiveLookingWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    @objc(hasKeyAppearance) var harnessHasKeyAppearance: Bool { true }
    @objc(hasMainAppearance) var harnessHasMainAppearance: Bool { true }
    @objc(_hasKeyAppearance) var harnessPrivateHasKeyAppearance: Bool { true }
    @objc(_hasMainAppearance) var harnessPrivateHasMainAppearance: Bool { true }
    @objc(_hasActiveAppearance) var harnessHasActiveAppearance: Bool { true }
    @objc(_hasActiveAppearanceIgnoringKeyFocus) var harnessHasActiveAppearanceIgnoringKeyFocus: Bool { true }
    @objc(_hasActiveControls) var harnessHasActiveControls: Bool { true }
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func harnessHasActiveAppearance(forStandardWindowButton button: Int) -> Bool { true }
}

@MainActor
func settle(_ seconds: TimeInterval = 0.4) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

/// Renders `view` (and its subviews) offscreen at `renderScale`.
@MainActor
func snapshot(_ view: NSView) -> NSBitmapImageRep {
    let bounds = view.bounds
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((bounds.width * renderScale).rounded()),
        pixelsHigh: Int((bounds.height * renderScale).rounded()),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = bounds.size
    view.cacheDisplay(in: bounds, to: rep)
    return rep
}

/// Places the rendered window on a soft neutral card with a subtle shadow.
@MainActor
func composite(window rep: NSBitmapImageRep, cornerRadius: CGFloat) -> NSBitmapImageRep {
    let windowSize = rep.size
    let canvasSize = NSSize(width: windowSize.width + margin * 2, height: windowSize.height + margin * 2)
    let scale = min(renderScale, maxOutputWidth / canvasSize.width)

    let out = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int((canvasSize.width * scale).rounded()),
        pixelsHigh: Int((canvasSize.height * scale).rounded()),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    out.size = canvasSize

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: out)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx

    // Background card: soft neutral gradient that reads well on light and dark pages.
    let bgPath = NSBezierPath(roundedRect: NSRect(origin: .zero, size: canvasSize), xRadius: 18, yRadius: 18)
    NSGradient(
        starting: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1),
        ending: NSColor(srgbRed: 0.86, green: 0.88, blue: 0.92, alpha: 1)
    )!.draw(in: bgPath, angle: -90)

    let windowRect = NSRect(x: margin, y: margin, width: windowSize.width, height: windowSize.height)
    let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // Shadow
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 18
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.set()
    NSColor.white.setFill()
    windowPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Window content, clipped to the rounded window shape
    NSGraphicsContext.saveGraphicsState()
    windowPath.addClip()
    rep.draw(in: windowRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    // Hairline border like a real macOS window
    NSColor.black.withAlphaComponent(0.18).setStroke()
    let border = NSBezierPath(roundedRect: windowRect.insetBy(dx: 0.25, dy: 0.25), xRadius: cornerRadius, yRadius: cornerRadius)
    border.lineWidth = 0.5
    border.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return out
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Screenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try data.write(to: url)
    print("wrote \(url.lastPathComponent) (\(rep.pixelsWide)×\(rep.pixelsHigh), \(data.count / 1024) KB)")
}

/// Renders a window including its title bar (the window's frame view).
@MainActor
func renderWindow(_ window: NSWindow, name: String) throws {
    window.appearance = NSAppearance(named: .aqua)
    window.contentView?.layoutSubtreeIfNeeded()
    settle()
    guard let frameView = window.contentView?.superview else { return }
    let raw = snapshot(frameView)
    if debugDirectory != nil {
        // Report scroll views whose content does not fit (clipped or scrollable content).
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        for scrollView in scrollViews(in: frameView) {
            let content = scrollView.documentView?.frame.height ?? 0
            let visible = scrollView.contentView.bounds.height
            print("  \(name): scroll content \(content) pt, visible \(visible) pt, overflow \(content - visible) pt")
        }
    }
    if let debugDirectory {
        try writePNG(raw, to: debugDirectory.appendingPathComponent("\(name)\(fileSuffix).raw.png"))
    }
    let final = composite(window: raw, cornerRadius: 12)
    try writePNG(final, to: outputDirectory.appendingPathComponent("\(name)\(fileSuffix).png"))
}

// MARK: - Shots

@MainActor
func demoAnnotations() -> [AnnotationItem] {
    let size = DemoContent.imageSize
    func n(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / size.width, y: y / size.height) }

    let peak = DemoContent.barRect(DemoContent.barCount - 1).insetBy(dx: -9, dy: -9)
    let table = DemoContent.tableRect
    let kpi = DemoContent.kpiRects

    return [
        // Redact the order list
        AnnotationItem(tool: .blur, startPoint: n(table.minX + 8, table.minY + 42),
                       endPoint: n(table.maxX - 8, table.maxY - 10), color: .red, lineWidth: 4),
        // Highlight the best month
        AnnotationItem(tool: .rectangle, startPoint: n(peak.minX, peak.minY),
                       endPoint: n(peak.maxX, peak.maxY), color: .red, lineWidth: 4),
        // Text annotations are anchored at the bottom-left corner of the text.
        AnnotationItem(tool: .text, startPoint: n(224, 264), endPoint: n(224, 264),
                       color: .red, lineWidth: 4,
                       text: DemoContent.strings(for: currentLanguage).annotation),
        AnnotationItem(tool: .arrow, startPoint: n(352, 254),
                       endPoint: n(peak.minX - 6, peak.minY + 30), color: .red, lineWidth: 4),
        // Numbered steps
        AnnotationItem(tool: .stepNumber, startPoint: n(kpi[0].maxX - 4, kpi[0].minY + 4),
                       endPoint: n(kpi[0].maxX - 4, kpi[0].minY + 4), color: .blue, lineWidth: 4, stepNumber: 1),
        AnnotationItem(tool: .stepNumber, startPoint: n(kpi[1].maxX - 4, kpi[1].minY + 4),
                       endPoint: n(kpi[1].maxX - 4, kpi[1].minY + 4), color: .blue, lineWidth: 4, stepNumber: 2)
    ]
}

@MainActor
func renderEditor() throws {
    let vm = EditorViewModel(image: DemoContent.makeImage(language: currentLanguage))
    let annotations = demoAnnotations()
    vm.annotations = annotations
    vm.undoStack = (0..<annotations.count).map { Array(annotations.prefix($0)) }
    vm.selectedTool = .arrow
    vm.selectedColor = .red
    vm.lineWidth = 4
    vm.nextStepNumber = 3

    let hosting = NSHostingController(rootView: EditorView(viewModel: vm))
    let window = ActiveLookingWindow(contentViewController: hosting)
    window.title = L10n.tr("editor.windowTitle")
    window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
    window.setContentSize(NSSize(width: 800, height: 560))
    window.isReleasedWhenClosed = false
    try renderWindow(window, name: "editor")
}

@MainActor
func renderSettings() throws {
    let hosting = NSHostingController(rootView: SettingsView())
    let window = ActiveLookingWindow(contentViewController: hosting)
    window.title = L10n.tr("settings.windowTitle")
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    try renderWindow(window, name: "settings")
}

// MARK: - Text annotation check

/// RGBA8 pixels of a bitmap, top row first.
struct Pixels {
    let width: Int
    let height: Int
    let data: [UInt8]

    init(_ rep: NSBitmapImageRep) {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        self.width = width
        self.height = height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        buffer.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        data = buffer
    }

    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    func difference(to other: Pixels, x: Int, y: Int, offsetX: Int = 0, offsetY: Int = 0) -> Int {
        let a = pixel(x, y), b = other.pixel(x + offsetX, y + offsetY)
        return max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }
}

/// Bounding box of the pixels where `annotated` differs from `clean` (at `offset` in `annotated`).
func changedBox(clean: Pixels, annotated: Pixels, offsetX: Int, offsetY: Int) -> CGRect? {
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<clean.height {
        for x in 0..<clean.width where clean.difference(to: annotated, x: x, y: y, offsetX: offsetX, offsetY: offsetY) > 24 {
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// Renders a text annotation once through the editor (preview) and once through the export
/// path, at the same pixel scale, and checks that both place it identically.
@MainActor
func verifyTextAnnotation(outputDirectory: URL) throws -> Bool {
    let image = DemoContent.makeImage(language: currentLanguage)
    let item = AnnotationItem(
        tool: .text, startPoint: CGPoint(x: 0.3, y: 0.55), endPoint: CGPoint(x: 0.3, y: 0.55),
        color: .red, lineWidth: 4, text: DemoContent.strings(for: currentLanguage).annotation
    )

    // Export path
    guard let exported = ImageRendererService.shared.render(image: image, annotations: [item]),
          let exportedCG = exported.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("export failed")
        return false
    }
    let exportRep = NSBitmapImageRep(cgImage: exportedCG)
    let clean = Pixels(NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!))
    let exportPixels = Pixels(exportRep)

    // Preview path: a window large enough that the canvas shows the image 1:1 (in points),
    // rendered at 2x, i.e. at the image's pixel size.
    let vm = EditorViewModel(image: image)
    vm.annotations = [item]
    let window = ActiveLookingWindow(contentViewController: NSHostingController(rootView: EditorView(viewModel: vm)))
    window.setContentSize(NSSize(width: 900, height: 700))
    window.appearance = NSAppearance(named: .aqua)
    window.contentView?.layoutSubtreeIfNeeded()
    settle()
    let editorRep = snapshot(window.contentView!)
    let editor = Pixels(editorRep)

    // Locate the canvas: scan from the editor's center to the dark surround.
    let cy = editor.height / 2, cx = editor.width / 2
    func isDark(_ p: (Int, Int, Int)) -> Bool { p.0 < 40 && p.1 < 40 && p.2 < 40 }
    var left = cx; while left > 0, !isDark(editor.pixel(left - 1, cy)) { left -= 1 }
    var top = cy; while top > 0, !isDark(editor.pixel(cx, top - 1)) { top -= 1 }
    let crop = editorRep.cgImage!.cropping(to: CGRect(x: left, y: top, width: clean.width, height: clean.height))!
    let previewRep = NSBitmapImageRep(cgImage: crop)

    try writePNG(exportRep, to: outputDirectory.appendingPathComponent("text-export.png"))
    try writePNG(previewRep, to: outputDirectory.appendingPathComponent("text-preview.png"))

    let exportBox = changedBox(clean: clean, annotated: exportPixels, offsetX: 0, offsetY: 0)
    let previewBox = changedBox(clean: clean, annotated: editor, offsetX: left, offsetY: top)
    print("canvas origin in editor: \(left),\(top)")
    print("export  annotation box: \(String(describing: exportBox))")
    print("preview annotation box: \(String(describing: previewBox))")

    // Pixel difference inside the annotation
    var maxDiff = 0, total = 0, count = 0
    if let box = exportBox {
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) {
                let d = exportPixels.difference(to: editor, x: x, y: y, offsetX: left, offsetY: top)
                maxDiff = max(maxDiff, d); total += d; count += 1
            }
        }
    }
    let mean = count > 0 ? Double(total) / Double(count) : 0
    print(String(format: "difference inside the box: mean %.2f, max %d (of 255)", mean, maxDiff))

    let boxesMatch: Bool = {
        guard let a = exportBox, let b = previewBox else { return false }
        return abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1
            && abs(a.maxX - b.maxX) <= 1 && abs(a.maxY - b.maxY) <= 1
    }()
    print(boxesMatch && mean < 4 ? "OK: preview matches export" : "MISMATCH")
    return boxesMatch && mean < 4
}

// MARK: - Main

let currentLanguage = Bundle.main.preferredLocalizations.first ?? "en"

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    app.appearance = NSAppearance(named: .aqua)
    app.finishLaunching()

    print("language: \(currentLanguage)")
    do {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        if let debugDirectory {
            try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
        }
        if let verifyTextDirectory {
            try FileManager.default.createDirectory(at: verifyTextDirectory, withIntermediateDirectories: true)
            exit(try verifyTextAnnotation(outputDirectory: verifyTextDirectory) ? 0 : 1)
        }
        if onlyShot == nil || onlyShot == "editor" { try renderEditor() }
        if onlyShot == nil || onlyShot == "settings" { try renderSettings() }
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}
exit(0)
