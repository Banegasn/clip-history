import Foundation

/// The three kinds of content we capture from the pasteboard.
enum ClipKind: String {
    case text
    case image
    case file
}

/// A single clipboard entry as held in memory and shown in the panel.
///
/// To keep RAM low with a 200-item history that may contain screenshots, the
/// in-memory item carries only a small `thumb` (downscaled PNG). The full image
/// payload lives in SQLite and is loaded on demand (`ClipboardStore.fullData`)
/// at paste time.
struct ClipItem: Identifiable, Hashable {
    let id: Int64
    let kind: ClipKind
    /// Text content for `.text`; newline-joined file paths for `.file`; nil for `.image`.
    let text: String?
    /// Small PNG thumbnail for `.image`; nil otherwise.
    let thumb: Data?
    let createdAt: Date

    /// First non-empty line — compact label (logs, single-line contexts).
    var preview: String {
        switch kind {
        case .image:
            return "Image"
        case .text, .file:
            let raw = text ?? ""
            let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? raw
            return firstLine.trimmingCharacters(in: .whitespaces)
        }
    }

    /// Full (trimmed) text for the row — rendered with a 2-line limit so
    /// multi-line clips show a couple of lines with a trailing ellipsis.
    var displayText: String {
        switch kind {
        case .image: return "Image"
        case .text, .file: return (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var hasMoreThanOneLine: Bool {
        (text ?? "").contains(where: \.isNewline)
    }

    /// Lowercased haystack for search matching.
    var searchText: String {
        (text ?? kind.rawValue).lowercased()
    }
}
