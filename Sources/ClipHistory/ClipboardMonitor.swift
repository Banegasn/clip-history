import AppKit

/// Polls `NSPasteboard.general.changeCount` (macOS has no clipboard-change
/// notification) and records new content into the store. ~0.4s cadence matches
/// what mainstream clipboard managers use — responsive without busy-spinning.
final class ClipboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int
    /// Called on the main thread after a new item is recorded, so the UI refreshes.
    var onChange: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Tell the monitor "this pasteboard state is ours" so our own writes
    /// (placing an item back on the clipboard to paste it) aren't re-recorded.
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Respect apps that mark content transient/concealed (password managers).
        if let types = pb.types,
           types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) ||
           types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) {
            return
        }

        guard let captured = capture(pb) else { return }
        store.insert(kind: captured.kind, text: captured.text, blob: captured.blob, thumb: captured.thumb)
        onChange?()
    }

    /// Reads the highest-value representation present: files > image > text.
    private func capture(_ pb: NSPasteboard) -> (kind: ClipKind, text: String?, blob: Data?, thumb: Data?)? {
        // Files / Finder copies.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            return (.file, paths, nil, nil)
        }

        // Images (normalize TIFF/other to PNG).
        if let png = imageAsPNG(pb) {
            return (.image, nil, png, ImageUtil.thumbnail(from: png))
        }

        // Plain / rich text.
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.text, s, nil, nil)
        }

        return nil
    }

    private func imageAsPNG(_ pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        if let tiff = pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }
}
