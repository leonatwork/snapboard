import SwiftUI
import AppKit

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var image: NSImage
    @Published var annotations: [AnnotationItem] = []
    @Published var undoStack: [[AnnotationItem]] = []
    @Published var redoStack: [[AnnotationItem]] = []

    @Published var selectedTool: AnnotationTool = .rectangle
    @Published var selectedColor: AnnotationColor = .red
    @Published var lineWidth: CGFloat = 4.0

    @Published var currentDraft: AnnotationItem?
    @Published var currentText: String = "Text"
    @Published var nextStepNumber: Int = 1

    var onClose: (() -> Void)?

    init(image: NSImage) {
        self.image = image
    }

    func startDrawing(at point: CGPoint, in size: CGSize) {
        let normalized = CGPoint(x: point.x / size.width, y: point.y / size.height)

        switch selectedTool {
        case .circle, .rectangle, .arrow, .blur:
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
            // Text is placed directly on tap
            saveForUndo()
            let item = AnnotationItem(
                tool: .text,
                startPoint: normalized,
                endPoint: normalized,
                color: selectedColor,
                lineWidth: lineWidth,
                text: currentText.isEmpty ? "Hinweis" : currentText
            )
            annotations.append(item)
        case .stepNumber:
            // Step badge placed directly on tap
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
        guard var draft = currentDraft else { return }
        let normalized = CGPoint(
            x: max(0, min(1, point.x / size.width)),
            y: max(0, min(1, point.y / size.height))
        )

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
        // Convert to full-res NSImage with annotations
        if let renderedImage = ImageRendererService.shared.render(image: image, annotations: annotations) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([renderedImage])

            if AppState.shared.playSound {
                NSSound(named: "Tink")?.play()
            }
        }
        onClose?()
    }

    func saveAsFile() {
        guard let renderedImage = ImageRendererService.shared.render(image: image, annotations: annotations),
              let tiffData = renderedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Screenshot_\(Int(Date().timeIntervalSince1970)).png"

        if panel.runModal() == .OK, let url = panel.url {
            try? pngData.write(to: url)
        }
    }
}

struct EditorView: View {
    @ObservedObject var viewModel: EditorViewModel
    @State private var showingTextPrompt = false
    @State private var tempInputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 14) {
                // Tools
                HStack(spacing: 4) {
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
                                .frame(width: 30, height: 26)
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

                // Colors
                HStack(spacing: 6) {
                    ForEach(AnnotationColor.allCases) { ac in
                        Circle()
                            .fill(ac.color)
                            .frame(width: 18, height: 18)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: viewModel.selectedColor == ac ? 2.5 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                            )
                            .onTapGesture {
                                viewModel.selectedColor = ac
                            }
                    }
                }

                Divider().frame(height: 24)

                // Stroke Width
                HStack(spacing: 4) {
                    ForEach([2.0, 4.0, 7.0], id: \.self) { width in
                        Button {
                            viewModel.lineWidth = CGFloat(width)
                        } label: {
                            Circle()
                                .fill(Color.primary)
                                .frame(width: CGFloat(width * 1.8), height: CGFloat(width * 1.8))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .background(viewModel.lineWidth == CGFloat(width) ? Color.accentColor.opacity(0.2) : Color.clear)
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
                    }
                    .disabled(viewModel.undoStack.isEmpty)
                    .help("Rückgängig (⌘Z)")

                    Button {
                        viewModel.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(viewModel.redoStack.isEmpty)
                    .help("Wiederholen (⌘⇧Z)")

                    Button {
                        viewModel.clearAll()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(viewModel.annotations.isEmpty)
                    .help("Alle Annotationen löschen")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Screenshot Drawing Canvas
            ZStack {
                Color.black.opacity(0.85)

                GeometryReader { geo in
                    let canvasSize = calculateFittedSize(imageSize: viewModel.image.size, in: geo.size)

                    ZStack {
                        // Base Screenshot Image
                        Image(nsImage: viewModel.image)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: canvasSize.width, height: canvasSize.height)

                        // Rendered Vector Annotation Overlays
                        Canvas { context, size in
                            // Draw completed annotations
                            for item in viewModel.annotations {
                                draw(item: item, in: &context, size: size)
                            }
                            // Draw live drag draft
                            if let draft = viewModel.currentDraft {
                                draw(item: draft, in: &context, size: size)
                            }
                        }
                        .frame(width: canvasSize.width, height: canvasSize.height)
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let localPt = CGPoint(
                                    x: value.location.x - (geo.size.width - canvasSize.width) / 2,
                                    y: value.location.y - (geo.size.height - canvasSize.height) / 2
                                )
                                if viewModel.currentDraft == nil {
                                    viewModel.startDrawing(at: localPt, in: canvasSize)
                                } else {
                                    viewModel.updateDrawing(to: localPt, in: canvasSize)
                                }
                            }
                            .onEnded { _ in
                                viewModel.finishDrawing()
                            }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom Actions Bar
            HStack {
                Button("Abbrechen (ESC)") {
                    viewModel.onClose?()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if viewModel.selectedTool == .text {
                    Button("Text bearbeiten: \"\(viewModel.currentText)\"") {
                        tempInputText = viewModel.currentText
                        showingTextPrompt = true
                    }
                    .buttonStyle(.accessoryBar)
                }

                Button("Speichern als... (⌘S)") {
                    viewModel.saveAsFile()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("In Zwischenablage kopieren (⌘C)") {
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
        .frame(minWidth: 700, minHeight: 520)
        .sheet(isPresented: $showingTextPrompt) {
            VStack(spacing: 16) {
                Text("Text eingeben")
                    .font(.headline)
                TextField("Hinweistext...", text: $tempInputText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                HStack {
                    Button("Abbrechen") {
                        showingTextPrompt = false
                    }
                    Button("Übernehmen") {
                        viewModel.currentText = tempInputText
                        showingTextPrompt = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
    }

    private func calculateFittedSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0 && imageSize.height > 0 else { return containerSize }
        let aspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        if containerAspect > aspect {
            let h = min(imageSize.height, containerSize.height - 20)
            return CGSize(width: h * aspect, height: h)
        } else {
            let w = min(imageSize.width, containerSize.width - 20)
            return CGSize(width: w, height: w / aspect)
        }
    }

    private func draw(item: AnnotationItem, in context: inout GraphicsContext, size: CGSize) {
        let start = CGPoint(x: item.startPoint.x * size.width, y: item.startPoint.y * size.height)
        let end = CGPoint(x: item.endPoint.x * size.width, y: item.endPoint.y * size.height)
        let color = item.color.color
        let strokeStyle = StrokeStyle(lineWidth: item.lineWidth, lineCap: .round, lineJoin: .round)

        switch item.tool {
        case .circle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(Path(ellipseIn: rect), with: .color(color), style: strokeStyle)

        case .rectangle:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            context.stroke(Path(roundedRect: rect, cornerRadius: item.lineWidth), with: .color(color), style: strokeStyle)

        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), style: strokeStyle)

            let headLength = max(10.0, item.lineWidth * 3.0)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let arrowAngle = CGFloat.pi / 6.0

            let pt1 = CGPoint(
                x: end.x - headLength * cos(angle - arrowAngle),
                y: end.y - headLength * sin(angle - arrowAngle)
            )
            let pt2 = CGPoint(
                x: end.x - headLength * cos(angle + arrowAngle),
                y: end.y - headLength * sin(angle + arrowAngle)
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
                style: StrokeStyle(lineWidth: item.lineWidth * 3.0, lineCap: .square, lineJoin: .miter)
            )

        case .blur:
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            // Live overlay for blur box
            context.fill(Path(rect), with: .color(Color.gray.opacity(0.55)))
            context.stroke(Path(rect), with: .color(Color.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

        case .text:
            guard !item.text.isEmpty else { break }
            let text = Text(item.text)
                .font(.system(size: max(13, item.lineWidth * 3.5), weight: .bold))
                .foregroundColor(color)
            let resolved = context.resolve(text)
            context.draw(resolved, at: start)

        case .stepNumber:
            let radius = max(11.0, item.lineWidth * 2.8)
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
