import AppKit
import CoreGraphics

/// Synthesizes a ⌘V keystroke into whichever app is frontmost.
///
/// Posting keyboard events requires the app to be trusted for Accessibility.
/// We re-activate the app that was frontmost when the panel opened, wait a beat
/// for activation, then post the keystroke so it lands in that app.
enum Paster {
    private static let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V

    static func paste(into app: NSRunningApplication?) {
        // Bring the previously-focused app back to the front first.
        app?.activate()

        // Give focus time to actually return to the target app (and its text
        // field to become first responder) before posting ⌘V. 0.10s was too
        // tight on slower activations; 0.18s is comfortably reliable.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let source = CGEventSource(stateID: .combinedSessionState)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
