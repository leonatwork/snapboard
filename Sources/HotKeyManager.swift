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
    private var hotKeyRef: EventHotKeyRef?
    private let screenieHotKeyID: UInt32 = 1
    private let signature: OSType = 0x5343524E // "SCRN"

    var onTrigger: (@MainActor () -> Void)?

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

    func registerDefaultHotKey() {
        unregisterHotKey()

        // Carbon modifiers:
        // cmdKey: 0x0100 (256)
        // shiftKey: 0x0200 (512)
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        // Key code for '1' is 18 (kVK_ANSI_1)
        let keyCode: UInt32 = 18

        let hotKeyID = EventHotKeyID(signature: signature, id: screenieHotKeyID)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            logger.info("Successfully registered global shortcut: Cmd + Shift + 1")
        } else {
            logger.error("Failed to register hotkey with status: \(status)")
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func handleHotKeyTriggered(id: UInt32) {
        if id == screenieHotKeyID {
            logger.info("Cmd + Shift + 1 shortcut triggered!")
            onTrigger?()
        }
    }

    deinit {
        // Cleanup event handler and hotkey if needed
    }
}
