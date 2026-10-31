import AppKit
import XCTest
@testable import Snapboard

@MainActor
final class EditorDrawingTests: XCTestCase {
    private let canvasSize = CGSize(width: 200, height: 100)
    private let start = CGPoint(x: 40, y: 30)
    private let movements = [CGPoint(x: 80, y: 50), CGPoint(x: 160, y: 90)]

    private func makeModel(tool: AnnotationTool) -> EditorViewModel {
        let model = EditorViewModel(image: NSImage(size: canvasSize))
        model.selectedTool = tool
        model.selectedColor = .blue
        model.lineWidth = 7
        return model
    }

    // Mirrors the unchanged onChanged/onEnded routing, including repeated mouse movement.
    private func drawGesture(_ model: EditorViewModel, movements: [CGPoint]) {
        for point in [start] + movements {
            if model.currentDraft == nil {
                model.startDrawing(at: point, in: canvasSize)
            } else {
                model.updateDrawing(to: point, in: canvasSize)
            }
        }
        model.finishDrawing()
    }

    func testTextUsesOneDraftAndPreservesTextAndPlacement() async throws {
        for text in ["Regression", ""] {
            let model = makeModel(tool: .text)
            model.currentText = text
            model.startDrawing(at: start, in: canvasSize)

            XCTAssertTrue(model.annotations.isEmpty)
            XCTAssertTrue(model.undoStack.isEmpty)
            let draft = try XCTUnwrap(model.currentDraft)
            XCTAssertEqual(draft.tool, .text)
            XCTAssertEqual(draft.text, text.isEmpty ? L10n.tr("editor.defaultText") : text)
            XCTAssertEqual(draft.startPoint, CGPoint(x: 0.2, y: 0.3))
            XCTAssertEqual(draft.color, .blue)
            XCTAssertEqual(draft.lineWidth, 7)

            for point in movements {
                model.updateDrawing(to: point, in: canvasSize)
                XCTAssertEqual(model.currentDraft?.id, draft.id)
                XCTAssertTrue(model.annotations.isEmpty)
            }
            model.finishDrawing()

            XCTAssertNil(model.currentDraft)
            XCTAssertEqual(model.annotations.count, 1)
            let item = try XCTUnwrap(model.annotations.first)
            XCTAssertEqual(item.id, draft.id)
            XCTAssertEqual(item.text, draft.text)
            XCTAssertEqual(item.startPoint, draft.startPoint)
            XCTAssertEqual(model.nextStepNumber, 1)
            XCTAssertEqual(model.undoStack.count, 1)
            model.finishDrawing()
            XCTAssertEqual(model.annotations.count, 1)
            XCTAssertEqual(model.undoStack.count, 1)
        }
    }

    func testStepNumberCommitsAndIncrementsOncePerFinishedGesture() async throws {
        let model = makeModel(tool: .stepNumber)
        model.nextStepNumber = 4

        for number in 4...5 {
            let countBefore = model.annotations.count
            model.startDrawing(at: start, in: canvasSize)
            let draft = try XCTUnwrap(model.currentDraft)
            XCTAssertEqual(draft.stepNumber, number)
            XCTAssertEqual(model.annotations.count, countBefore)
            XCTAssertEqual(model.nextStepNumber, number)
            for point in movements {
                model.updateDrawing(to: point, in: canvasSize)
                XCTAssertEqual(model.currentDraft?.id, draft.id)
                XCTAssertEqual(model.currentDraft?.stepNumber, number)
                XCTAssertEqual(model.nextStepNumber, number)
            }
            model.finishDrawing()

            XCTAssertNil(model.currentDraft)
            XCTAssertEqual(model.annotations.count, countBefore + 1)
            let item = try XCTUnwrap(model.annotations.last)
            XCTAssertEqual(item.tool, .stepNumber)
            XCTAssertEqual(item.id, draft.id)
            XCTAssertEqual(item.stepNumber, number)
            XCTAssertEqual(item.startPoint, CGPoint(x: 0.2, y: 0.3))
            XCTAssertEqual(item.color, .blue)
            XCTAssertEqual(item.lineWidth, 7)
            XCTAssertEqual(model.nextStepNumber, number + 1)
            model.finishDrawing()
            XCTAssertEqual(model.annotations.count, countBefore + 1)
            XCTAssertEqual(model.nextStepNumber, number + 1)
        }
        XCTAssertEqual(model.annotations.map(\.stepNumber), [4, 5])
        XCTAssertEqual(model.undoStack.count, 2)
    }

    func testTextAndStepNumberGestureRoutingCreatesExactlyOneAnnotation() async throws {
        for tool in [AnnotationTool.text, .stepNumber] {
            for updates in [[], [movements[0]], movements + movements + movements] {
                let model = makeModel(tool: tool)
                drawGesture(model, movements: updates)

                XCTAssertEqual(model.annotations.count, 1, "\(tool), \(updates.count) movements")
                let item = try XCTUnwrap(model.annotations.first)
                XCTAssertEqual(item.tool, tool)
                XCTAssertEqual(item.startPoint, CGPoint(x: 0.2, y: 0.3))
                XCTAssertEqual(model.nextStepNumber, tool == .stepNumber ? 2 : 1)
                XCTAssertEqual(model.undoStack.count, 1)
                XCTAssertNil(model.currentDraft)
            }
        }
    }

    func testUndoRemovesExactlyOneTextOrStepNumberGestureAndRedoRestoresIt() async throws {
        for tool in [AnnotationTool.text, .stepNumber] {
            let model = makeModel(tool: .rectangle)
            drawGesture(model, movements: movements)
            let existing = model.annotations
            model.selectedTool = tool
            drawGesture(model, movements: movements)
            let completed = model.annotations

            XCTAssertEqual(completed.count, existing.count + 1)
            XCTAssertEqual(model.undoStack.count, 2)
            model.undo()
            XCTAssertEqual(model.annotations, existing)
            XCTAssertEqual(model.undoStack.count, 1)
            XCTAssertEqual(model.redoStack, [completed])
            model.redo()
            XCTAssertEqual(model.annotations, completed)
            XCTAssertEqual(model.undoStack.count, 2)
            XCTAssertTrue(model.redoStack.isEmpty)
        }
    }

    func testOtherToolsPreserveDraftGeometryPathsAndUndoRedo() async throws {
        for tool in [AnnotationTool.rectangle, .circle, .arrow, .blur, .pen, .highlighter] {
            let model = makeModel(tool: tool)
            model.startDrawing(at: start, in: canvasSize)
            let draft = try XCTUnwrap(model.currentDraft)
            XCTAssertTrue(model.annotations.isEmpty)
            XCTAssertTrue(model.undoStack.isEmpty)
            model.updateDrawing(to: movements[0], in: canvasSize)
            model.updateDrawing(to: CGPoint(x: 240, y: -10), in: canvasSize)
            XCTAssertEqual(model.currentDraft?.id, draft.id)
            XCTAssertTrue(model.annotations.isEmpty)
            model.finishDrawing()

            XCTAssertEqual(model.annotations.count, 1)
            let item = try XCTUnwrap(model.annotations.first)
            XCTAssertEqual(item.id, draft.id)
            XCTAssertEqual(item.tool, tool)
            XCTAssertEqual(item.startPoint, CGPoint(x: 0.2, y: 0.3))
            XCTAssertEqual(item.endPoint, CGPoint(x: 1, y: 0))
            let expectedPoints: [CGPoint] = tool == .pen || tool == .highlighter
                ? [CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.4, y: 0.5), CGPoint(x: 1, y: 0)]
                : []
            XCTAssertEqual(item.points, expectedPoints)
            XCTAssertEqual(item.color, .blue)
            XCTAssertEqual(item.lineWidth, 7)
            XCTAssertEqual(model.nextStepNumber, 1)
            XCTAssertNil(model.currentDraft)
            XCTAssertEqual(model.undoStack.count, 1)
            model.finishDrawing()
            XCTAssertEqual(model.annotations.count, 1)
            XCTAssertEqual(model.undoStack.count, 1)
            model.undo()
            XCTAssertTrue(model.annotations.isEmpty)
            model.redo()
            XCTAssertEqual(model.annotations, [item])
        }
    }
}
