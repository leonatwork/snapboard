import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    static let shared = EditorWindowController()

    private var window: NSWindow?
    private var viewModel: EditorViewModel?

    private override init() {
        super.init()
    }

    func show(image: NSImage) {
        if let existing = window, existing.isVisible {
            existing.close()
        }

        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let fitW = min(image.size.width + 60, screenSize.width * 0.9)
        let fitH = min(image.size.height + 140, screenSize.height * 0.9)
        let windowWidth = max(800, fitW)
        let windowHeight = max(600, fitH)

        let vm = EditorViewModel(image: image)
        self.viewModel = vm

        vm.onClose = { [weak self] in
            self?.window?.close()
        }

        let editorView = EditorView(viewModel: vm)
        let hostingController = NSHostingController(rootView: editorView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = L10n.tr("editor.windowTitle")
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: windowWidth, height: windowHeight))
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        self.viewModel = nil
        self.window = nil
    }
}
