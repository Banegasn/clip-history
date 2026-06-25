import AppKit
import SwiftUI

/// An NSPanel that is allowed to become key (so the search field can receive
/// typing) even though the app is a background/accessory agent.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating history panel and bridges it to the SwiftUI view + model.
final class PanelController: NSObject, NSWindowDelegate {
    let model = PanelModel()
    private var panel: KeyablePanel?

    override init() {
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        // Center on the screen that currently has the mouse / key focus.
        if let screen = NSScreen.main {
            let frame = panel.frame
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: visible.midX - frame.width / 2,
                y: visible.midY - frame.height / 2 + visible.height * 0.08
            )
            panel.setFrameOrigin(origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Ask the search field to take focus (panel is reused across shows, so
        // first-responder isn't guaranteed to be restored on reopen).
        model.focusRequest += 1
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> KeyablePanel {
        // Borderless so there's no title-bar gap; the SwiftUI view supplies its
        // own rounded background and the window draws the shadow underneath.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.delegate = self

        let host = NSHostingView(rootView: HistoryView(model: model))
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    // Dismiss when the user clicks away / focus leaves the panel.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
