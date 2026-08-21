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
        // Calculate appropriate window size based on image and screen size
        let screenSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let maxW = min(image.size.width + 80, screenSize.width * 0.85)
        let maxH = min(image.size.height + 120, screenSize.height * 0.85)
        let windowWidth = max(750, maxW)
        let windowHeight = max(550, maxH)

        let vm = EditorViewModel(image: image)
        self.viewModel = vm

        vm.onClose = { [weak self] in
            self?.window?.close()
        }

        let editorView = EditorView(viewModel: vm)
        let hostingController = NSHostingController(rootView: editorView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = "Screenie Editor"
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
