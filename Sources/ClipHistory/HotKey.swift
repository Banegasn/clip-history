import AppKit
import Carbon.HIToolbox

/// A single global hotkey registered via Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are the most reliable system-wide shortcut on macOS and,
/// unlike a CGEvent tap, do NOT require Accessibility permission just to listen.
/// The fire callback runs on the main run loop.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPressed: () -> Void

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_V` (9) for "V".
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | shiftKey`.
    init(keyCode: UInt32, modifiers: UInt32, onPressed: @escaping () -> Void) {
        self.onPressed = onPressed

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let me = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            me.onPressed()
            return noErr
        }, 1, &eventSpec, selfPtr, &handlerRef)

        // 'CLIP' signature, id 1 — arbitrary but stable identifier.
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C4950), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
