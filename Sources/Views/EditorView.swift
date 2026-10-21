import SwiftUI
import AppKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var image: NSImage {
        didSet { imagePixelSize = Self.pixelSize(of: image) }
    }
    /// Pixel size of `image`, the coordinate space of the exported image.
    private(set) var imagePixelSize: CGSize
    @Published var annotations: [AnnotationItem] = []
    @Published var undoStack: [[AnnotationItem]] = []
    @Published var redoStack: [[AnnotationItem]] = []

    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var selectedColor: AnnotationColor = .red
    @Published var lineWidth: CGFloat = 4.0

    @Published var currentDraft: AnnotationItem?
    @Published var currentText: String = L10n.tr("editor.defaultText")
    @Published var nextStepNumber: Int = 1

    var onClose: (() -> Void)?

    // Small seams for testing export actions without the system clipboard or modal UI.
    var pasteboard: NSPasteboard = .general
    var selectSaveURL: () -> URL? = {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snapboard_\(Int(Date().timeIntervalSince1970)).png"
        return panel.runModal() == .OK ? panel.url : nil
    }
    var presentExportError: (String, Error) -> Void = { title, error in
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: L10n.tr("common.ok"))
        alert.runModal()
    }

    init(image: NSImage) {
        self.image = image
        self.imagePixelSize = Self.pixelSize(of: image)
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return image.size
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
            let bitmap = try renderExportBitmap()
            let pngData = try ImageExport.data(from: bitmap, using: .png)
            let tiffData = try ImageExport.data(from: bitmap, using: .tiff)
            let item = NSPasteboardItem()
            guard item.setData(pngData, forType: .png),
                  item.setData(tiffData, forType: .tiff) else {
                throw EditorExportError.clipboardFailed
            }

            // Encode both formats before replacing the existing clipboard contents.
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else {
                throw EditorExportError.clipboardFailed
            }

            if AppState.shared.playSound {
                NSSound(named: "Tink")?.play()
            }
            onClose?()
        } catch {
            presentExportError(L10n.tr("editor.export.copyFailed"), error)
        }
    }

    func saveAsFile() {
        do {
            let bitmap = try renderExportBitmap()
            let pngData = try ImageExport.data(from: bitmap, using: .png)
            guard let url = selectSaveURL() else { return }
            try pngData.write(to: url)
        } catch {
            presentExportError(L10n.tr("editor.export.saveFailed"), error)
        }
    }

    private func renderExportBitmap() throws -> NSBitmapImageRep {
        guard let renderedImage = ImageRendererService.shared.render(image: image, annotations: annotations) else {
            throw EditorExportError.renderFailed
        }
        return try ImageExport.bitmap(image: renderedImage)
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
                        // Original Screenshot
                        Image(nsImage: viewModel.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: canvasSize.width, height: canvasSize.height)

                        // Vector Drawing Canvas
                        Canvas { context, size in
                            for item in viewModel.annotations {
                                draw(item: item, in: &context, size: size)
                            }
                            if let draft = viewModel.currentDraft {
                                draw(item: draft, in: &context, size: size)
                            }
                        }
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

    private func draw(item: AnnotationItem, in context: inout GraphicsContext, size: CGSize) {
        let start = CGPoint(x: item.startPoint.x * size.width, y: item.startPoint.y * size.height)
        let end = CGPoint(x: item.endPoint.x * size.width, y: item.endPoint.y * size.height)
        let color = item.color.color
        let strokeStyle = StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round)

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        switch item.tool {
        case .rectangle:
            context.stroke(Path(roundedRect: rect, cornerRadius: item.lineWidth), with: .color(color), style: strokeStyle)

        case .circle:
            context.stroke(Path(ellipseIn: rect), with: .color(color), style: strokeStyle)

        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: strokeStyle)

            let headLength = max(12.0, item.lineWidth * 3.5)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let headAngle = CGFloat.pi / 6.0

            let pt1 = CGPoint(
                x: end.x - headLength * cos(angle - headAngle),
                y: end.y - headLength * sin(angle - headAngle)
            )
            let pt2 = CGPoint(
                x: end.x - headLength * cos(angle + headAngle),
                y: end.y - headLength * sin(angle + headAngle)
            )

            var headPath = Path()
            headPath.move(to: end)
            headPath.addLine(to: pt1)
            headPath.addLine(to: pt2)
            headPath.closeSubpath()
            context.fill(headPath, with: .color(color))

        case .pen:
            guard item.points.count > 1 else { break }
            var path = Path()
            let first = CGPoint(x: item.points[0].x * size.width, y: item.points[0].y * size.height)
            path.move(to: first)
            for pt in item.points.dropFirst() {
                path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
            }
            context.stroke(path, with: .color(color), style: strokeStyle)

        case .highlighter:
            guard item.points.count > 1 else { break }
            var path = Path()
            let first = CGPoint(x: item.points[0].x * size.width, y: item.points[0].y * size.height)
            path.move(to: first)
            for pt in item.points.dropFirst() {
                path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
            }
            context.stroke(
                path,
                with: .color(color.opacity(0.4)),
                style: StrokeStyle(lineWidth: item.lineWidth * 3.5, lineCap: .square, lineJoin: .miter)
            )

        case .blur:
            // High contrast frosted overlay representation in SwiftUI canvas
            context.fill(Path(rect), with: .color(Color.gray.opacity(0.7)))
            context.stroke(Path(rect), with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

        case .text:
            // Same layout as the exported image, scaled from image pixels to the canvas.
            let pixelSize = viewModel.imagePixelSize
            guard let layout = TextAnnotationLayout(item: item, imagePixelSize: pixelSize) else { break }
            context.withCGContext { cgContext in
                cgContext.scaleBy(x: size.width / pixelSize.width, y: size.height / pixelSize.height)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
                layout.draw(flipped: true)
                NSGraphicsContext.restoreGraphicsState()
            }

        case .stepNumber:
            let radius = max(13.0, item.lineWidth * 3.2)
            let badgeRect = CGRect(x: start.x - radius, y: start.y - radius, width: radius * 2, height: radius * 2)

            context.fill(Path(ellipseIn: badgeRect), with: .color(color))
            context.stroke(Path(ellipseIn: badgeRect), with: .color(.white), style: StrokeStyle(lineWidth: 1.5))

            let numText = Text("\(item.stepNumber)")
                .font(.system(size: radius * 1.1, weight: .bold))
                .foregroundColor(.white)
            let resolvedNum = context.resolve(numText)
            context.draw(resolvedNum, at: start, anchor: .center)
        }
    }
}
