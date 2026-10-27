import SwiftUI
import AppKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var image: NSImage {
        didSet {
            imagePixelSize = Self.pixelSize(of: image)
            refreshPixelatedPreview(sourceChanged: true)
        }
    }
    /// Pixel size of `image`, the coordinate space of the exported image.
    private(set) var imagePixelSize: CGSize
    @Published var annotations: [AnnotationItem] = [] {
        didSet { refreshPixelatedPreview() }
    }
    /// Source plus completed pixelations, below all vector annotations like the export.
    @Published private(set) var pixelatedPreview: NSImage?
    private var pixelationRects: [CGRect] = []
    @Published var undoStack: [[AnnotationItem]] = []
    @Published var redoStack: [[AnnotationItem]] = []

    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var selectedColor: AnnotationColor = .red
    @Published var lineWidth: CGFloat = 4.0

    @Published var currentDraft: AnnotationItem?
    @Published var currentText: String = L10n.tr("editor.defaultText")
    @Published var nextStepNumber: Int = 1

    var onClose: (() -> Void)?

    private let pasteboard: NSPasteboard
    private let presentExportError: (Error) -> Void
    private let chooseSaveURL: () -> URL?

    init(
        image: NSImage,
        pasteboard: NSPasteboard = .general,
        presentExportError: ((Error) -> Void)? = nil,
        chooseSaveURL: (() -> URL?)? = nil
    ) {
        self.image = image
        self.imagePixelSize = Self.pixelSize(of: image)
        self.pasteboard = pasteboard
        self.presentExportError = presentExportError ?? Self.showExportError
        self.chooseSaveURL = chooseSaveURL ?? Self.showSavePanel
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
    }

    private func refreshPixelatedPreview(sourceChanged: Bool = false) {
        let blurItems = annotations.filter { $0.tool == .blur }
        let rects = blurItems.map {
            $0.cgRectInPixelSpace(width: Int(imagePixelSize.width), height: Int(imagePixelSize.height))
        }
        guard sourceChanged || rects != pixelationRects else { return }
        pixelationRects = rects
        pixelatedPreview = blurItems.isEmpty ? nil : ImageRendererService.shared.render(image: image, annotations: blurItems)
    }

    func startDrawing(at point: CGPoint, in size: CGSize) {
        guard size.width > 0 && size.height > 0 else { return }
        let nx = max(0, min(1, point.x / size.width))
        let ny = max(0, min(1, point.y / size.height))
        let normalized = CGPoint(x: nx, y: ny)

        switch selectedTool {
        case .rectangle, .circle, .arrow, .blur:
            currentDraft = AnnotationItem(
                tool: selectedTool,
                startPoint: normalized,
                endPoint: normalized,
                color: selectedColor,
                lineWidth: lineWidth
            )
        case .pen, .highlighter:
            currentDraft = AnnotationItem(
                tool: selectedTool,
                startPoint: normalized,
                endPoint: normalized,
                points: [normalized],
                color: selectedColor,
                lineWidth: lineWidth
            )
        case .text:
            saveForUndo()
            let item = AnnotationItem(
                tool: .text,
                startPoint: normalized,
                endPoint: normalized,
                color: selectedColor,
                lineWidth: lineWidth,
                text: currentText.isEmpty ? L10n.tr("editor.defaultText") : currentText
            )
            annotations.append(item)
        case .stepNumber:
            saveForUndo()
            let item = AnnotationItem(
                tool: .stepNumber,
                startPoint: normalized,
                endPoint: normalized,
                color: selectedColor,
                lineWidth: lineWidth,
                stepNumber: nextStepNumber
            )
            nextStepNumber += 1
            annotations.append(item)
        }
    }

    func updateDrawing(to point: CGPoint, in size: CGSize) {
        guard var draft = currentDraft, size.width > 0 && size.height > 0 else { return }
        let nx = max(0, min(1, point.x / size.width))
        let ny = max(0, min(1, point.y / size.height))
        let normalized = CGPoint(x: nx, y: ny)

        draft.endPoint = normalized
        if draft.tool == .pen || draft.tool == .highlighter {
            draft.points.append(normalized)
        }
        self.currentDraft = draft
    }

    func finishDrawing() {
        guard let draft = currentDraft else { return }
        saveForUndo()
        annotations.append(draft)
        currentDraft = nil
    }

    func saveForUndo() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func clearAll() {
        saveForUndo()
        annotations.removeAll()
        nextStepNumber = 1
    }

    func copyToClipboardAndClose() {
        do {
            let item = try renderForExport().pasteboardItem()
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                throw ImageExportError.clipboardFailed
            }

            if AppState.shared.playSound {
                NSSound(named: "Tink")?.play()
            }
            onClose?()
        } catch {
            presentExportError(error)
        }
    }

    func saveAsFile() {
        do {
            let pngData = try renderForExport().pngData()
            guard let url = chooseSaveURL() else { return }
            try pngData.write(to: url)
        } catch {
            presentExportError(error)
        }
    }

    private func renderForExport() throws -> ImageExport {
        guard let renderedImage = ImageRendererService.shared.render(image: image, annotations: annotations) else {
            throw ImageExportError.renderingFailed
        }
        return try ImageExport(image: renderedImage)
    }

    private static func showSavePanel() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snapboard_\(Int(Date().timeIntervalSince1970)).png"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func showExportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("editor.exportError.title")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }
}

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var showingTextPrompt = false
    @State private var tempInputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Tool Selector
                HStack(spacing: 3) {
                    ForEach(AnnotationTool.allCases) { tool in
                        Button {
                            viewModel.selectedTool = tool
                            if tool == .text {
                                tempInputText = viewModel.currentText
                                showingTextPrompt = true
                            }
                        } label: {
                            Image(systemName: tool.iconName)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 28)
                        }
                        .buttonStyle(.plain)
                        .background(viewModel.selectedTool == tool ? Color.accentColor : Color.clear)
                        .foregroundColor(viewModel.selectedTool == tool ? .white : .primary)
                        .cornerRadius(6)
                        .help(tool.title)
                    }
                }
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                Divider().frame(height: 24)

                // Color Selector
                HStack(spacing: 6) {
                    ForEach(AnnotationColor.allCases) { ac in
                        Circle()
                            .fill(ac.color)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: viewModel.selectedColor == ac ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.3), lineWidth: 1)
                            )
                            .onTapGesture {
                                viewModel.selectedColor = ac
                            }
                    }
                }

                Divider().frame(height: 24)

                // Line Width Selector
                HStack(spacing: 4) {
                    ForEach([2.0, 4.0, 7.0], id: \.self) { width in
                        Button {
                            viewModel.lineWidth = CGFloat(width)
                        } label: {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: CGFloat(width * 1.8), height: CGFloat(width * 1.8))
                                .frame(width: 26, height: 26)
                        }
                        .buttonStyle(.plain)
                        .background(viewModel.lineWidth == CGFloat(width) ? Color.accentColor.opacity(0.25) : Color.clear)
                        .cornerRadius(6)
                    }
                }

                Spacer()

                // Undo / Redo / Clear
                HStack(spacing: 6) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 13))
                    }
                    .disabled(viewModel.undoStack.isEmpty)
                    .help(L10n.tr("editor.undo"))

                    Button {
                        viewModel.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.system(size: 13))
                    }
                    .disabled(viewModel.redoStack.isEmpty)
                    .help(L10n.tr("editor.redo"))

                    Button {
                        viewModel.clearAll()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                    }
                    .disabled(viewModel.annotations.isEmpty)
                    .help(L10n.tr("editor.clearAll"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Canvas Area
            GeometryReader { geo in
                let canvasSize = calculateFittedSize(imageSize: viewModel.image.size, in: geo.size)

                ZStack {
                    Color.black.opacity(0.9)

                    // Canvas Container with exact fitted dimensions
                    ZStack {
                        AnnotationCanvas(viewModel: viewModel)
                            .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if viewModel.currentDraft == nil {
                                    viewModel.startDrawing(at: value.location, in: canvasSize)
                                } else {
                                    viewModel.updateDrawing(to: value.location, in: canvasSize)
                                }
                            }
                            .onEnded { _ in
                                viewModel.finishDrawing()
                            }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Bottom Bar
            HStack {
                Button(L10n.tr("editor.cancel")) {
                    viewModel.onClose?()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if viewModel.selectedTool == .text {
                    Button(L10n.format("editor.changeText", viewModel.currentText)) {
                        tempInputText = viewModel.currentText
                        showingTextPrompt = true
                    }
                    .buttonStyle(.accessoryBar)
                }

                Button(L10n.tr("editor.saveAs")) {
                    viewModel.saveAsFile()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button(L10n.tr("editor.copyToClipboard")) {
                    viewModel.copyToClipboardAndClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: .command)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 560)
        .sheet(isPresented: $showingTextPrompt) {
            VStack(spacing: 16) {
                Text(L10n.tr("editor.textPrompt.title"))
                    .font(.headline)
                TextField(L10n.tr("editor.textPrompt.placeholder"), text: $tempInputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                HStack {
                    Button(L10n.tr("common.cancel")) {
                        showingTextPrompt = false
                    }
                    Button(L10n.tr("editor.textPrompt.apply")) {
                        viewModel.currentText = tempInputText
                        showingTextPrompt = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
    }

    private func calculateFittedSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 && containerSize.width > 0 && containerSize.height > 0 else {
            return CGSize(width: 400, height: 300)
        }

        let padding: CGFloat = 24
        let maxW = max(100, containerSize.width - padding)
        let maxH = max(100, containerSize.height - padding)

        let aspect = imageSize.width / imageSize.height
        let containerAspect = maxW / maxH

        if containerAspect > aspect {
            let h = min(imageSize.height, maxH)
            return CGSize(width: h * aspect, height: h)
        } else {
            let w = min(imageSize.width, maxW)
            return CGSize(width: w, height: w / aspect)
        }
    }

}

/// The editor's fitted canvas, also rendered directly by the annotation harness.
@MainActor
struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeNSView(context: Context) -> AnnotationCanvasView {
        AnnotationCanvasView(frame: .zero)
    }

    func updateNSView(_ view: AnnotationCanvasView, context: Context) {
        view.viewModel = viewModel
        view.needsDisplay = true
    }
}

/// Draw directly into the destination context, rather than independently rasterizing
/// SwiftUI Image/Canvas layers at the screen's backing scale. Offscreen/Retina drawing
/// then uses the same pixel geometry, color conversion and antialiasing as export.
@MainActor
final class AnnotationCanvasView: NSView {
    var viewModel: EditorViewModel?

    override var isFlipped: Bool { true }

    // Drawing gestures belong to the enclosing SwiftUI canvas container.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let viewModel, let cgContext = NSGraphicsContext.current?.cgContext else { return }
        let pixelSize = viewModel.imagePixelSize
        let image = viewModel.pixelatedPreview ?? viewModel.image
        guard pixelSize.width > 0, pixelSize.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        cgContext.saveGState()
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
            cgContext.restoreGState()
        }
        cgContext.clip(to: bounds)
        cgContext.translateBy(x: bounds.minX, y: bounds.minY)
        cgContext.scaleBy(x: bounds.width / pixelSize.width, y: bounds.height / pixelSize.height)
        cgContext.translateBy(x: 0, y: pixelSize.height)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.interpolationQuality = .high
        cgContext.draw(cgImage, in: CGRect(origin: .zero, size: pixelSize))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: false)

        for item in viewModel.annotations where item.tool != .blur {
            ImageRendererService.shared.drawAnnotation(
                item, pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height)
            )
        }
        if let draft = viewModel.currentDraft {
            if draft.tool == .blur {
                let rect = draft.cgRectInPixelSpace(width: Int(pixelSize.width), height: Int(pixelSize.height))
                NSColor.gray.withAlphaComponent(0.7).setFill()
                NSBezierPath(rect: rect).fill()
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let border = NSBezierPath(rect: rect)
                let previewScale = pixelSize.width / max(1, bounds.width)
                border.lineWidth = 1.5 * previewScale
                border.setLineDash([4 * previewScale, 4 * previewScale], count: 2, phase: 0)
                border.stroke()
            } else {
                ImageRendererService.shared.drawAnnotation(
                    draft, pixelWidth: Int(pixelSize.width), pixelHeight: Int(pixelSize.height)
                )
            }
        }
    }
}
