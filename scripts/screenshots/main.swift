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
        // The editor preview centers the text on its anchor point, so the anchor sits
        // roughly in the middle of the label.
        AnnotationItem(tool: .text, startPoint: n(262, 240), endPoint: n(262, 240),
                       color: .red, lineWidth: 4,
                       text: DemoContent.strings(for: currentLanguage).annotation),
        AnnotationItem(tool: .arrow, startPoint: n(406, 252),
                       endPoint: n(peak.minX - 6, peak.minY + 48), color: .red, lineWidth: 4),
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
        try renderEditor()
        try renderSettings()
    } catch {
        FileHandle.standardError.write("error: \(error.localizedDescription)\n".data(using: .utf8)!)
        exit(1)
    }
}
exit(0)
