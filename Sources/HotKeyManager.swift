import AppKit
import Carbon
import os.log

private let logger = Logger(subsystem: "com.leon.screenie", category: "HotKeyManager")

// Global C callback function for Carbon Event Handler
private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    theEvent: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let theEvent = theEvent else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        theEvent,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    if status == noErr {
        DispatchQueue.main.async {
            Task { @MainActor in
                HotKeyManager.shared.handleHotKeyTriggered(id: hotKeyID.id)
            }
        }
        return noErr
    }

    return OSStatus(eventNotHandledErr)
}

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef1: EventHotKeyRef?
    private var hotKeyRef2: EventHotKeyRef?

    private let directHotKeyID: UInt32 = 1
    private let editHotKeyID: UInt32 = 2
    private let signature: OSType = 0x5343524E // "SCRN"

    var onTriggerDirect: (@MainActor () -> Void)?
    var onTriggerEdit: (@MainActor () -> Void)?

    private init() {
        setupEventHandler()
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        if status != noErr {
            logger.error("Failed to install Carbon event handler: \(status)")
        }
    }

    func registerHotKeys() {
        unregisterHotKeys()

        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        // Key code for '1' is 18 (Cmd + Shift + 1 -> Direct to clipboard)
        let hotKeyID1 = EventHotKeyID(signature: signature, id: directHotKeyID)
        let status1 = RegisterEventHotKey(
            18,
            modifiers,
            hotKeyID1,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef1
        )

        // Key code for '2' is 19 (Cmd + Shift + 2 -> Capture and Open in Editor)
        let hotKeyID2 = EventHotKeyID(signature: signature, id: editHotKeyID)
        let status2 = RegisterEventHotKey(
            19,
            modifiers,
            hotKeyID2,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef2
        )

        if status1 == noErr && status2 == noErr {
            logger.info("Successfully registered global shortcuts: ⌘⇧1 (Direct) & ⌘⇧2 (Edit)")
        } else {
            logger.error("Error registering hotkeys: status1=\(status1), status2=\(status2)")
        }
    }

    func unregisterHotKeys() {
        if let ref1 = hotKeyRef1 {
            UnregisterEventHotKey(ref1)
            self.hotKeyRef1 = nil
        }
        if let ref2 = hotKeyRef2 {
            UnregisterEventHotKey(ref2)
            self.hotKeyRef2 = nil
        }
    }

    func handleHotKeyTriggered(id: UInt32) {
        if id == directHotKeyID {
            logger.info("Cmd + Shift + 1 (Direct) triggered")
            onTriggerDirect?()
        } else if id == editHotKeyID {
            logger.info("Cmd + Shift + 2 (Edit) triggered")
            onTriggerEdit?()
        }
    }
}
