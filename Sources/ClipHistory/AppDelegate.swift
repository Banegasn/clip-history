import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    private let panelController = PanelController()
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?

    /// The app that was frontmost when the panel opened — where we paste back into.
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        setupMonitor()
        setupHotKey()
        promptForAccessibilityIfNeeded()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard",
                                     accessibilityDescription: "ClipHistory")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show History  ⇧⌘V", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClipHistory", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func setupPanel() {
        panelController.model.onPick = { [weak self] item in self?.paste(item) }
        panelController.model.onClose = { [weak self] in self?.panelController.hide() }
        panelController.model.onDelete = { [weak self] item in
            guard let self else { return }
            self.store.delete(id: item.id)
            self.panelController.model.items = self.store.all()
        }
    }

    private func setupMonitor() {
        monitor.onChange = { [weak self] in
            guard let self, self.panelController.isVisible else { return }
            self.panelController.model.items = self.store.all()
        }
        monitor.start()
    }

    private func setupHotKey() {
        // ⇧⌘V — "V" is virtual key code 9 (kVK_ANSI_V).
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V),
                        modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.showPanel()
        }
    }

    // MARK: - Actions

    @objc private func showPanel() {
        previousApp = NSWorkspace.shared.frontmostApplication
        panelController.model.query = ""
        panelController.model.expandedItem = nil
        panelController.model.items = store.all()
        panelController.show()
    }

    private func paste(_ item: ClipItem) {
        placeOnPasteboard(item)
        monitor.syncChangeCount() // our own write must not be re-recorded
        panelController.hide()
        Paster.paste(into: previousApp)
    }

    private func placeOnPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = store.fullData(for: item.id) {
                pb.setData(data, forType: .png)
            }
        case .file:
            let urls: [NSURL] = (item.text ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            if !urls.isEmpty { pb.writeObjects(urls) }
        }
    }

    @objc private func clearHistory() {
        store.clear()
        panelController.model.items = []
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func promptForAccessibilityIfNeeded() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            NSLog("ClipHistory: Accessibility permission required to paste with ⌘V. "
                + "Grant it in System Settings ▸ Privacy & Security ▸ Accessibility.")
        }
    }
}
