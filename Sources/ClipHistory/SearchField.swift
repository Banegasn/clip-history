import SwiftUI
import AppKit

/// A search input backed by `NSTextField` so we can intercept arrow keys and
/// Return *before* the field editor consumes them.
///
/// SwiftUI's `TextField` + `.onKeyPress` does not work here: the underlying
/// field editor eats ↑/↓ (caret movement) and ⏎, so key presses never bubble to
/// a parent's `.onKeyPress`. The idiomatic fix is the delegate's
/// `control(_:textView:doCommandBy:)`, which fires for command selectors like
/// `moveUp:` / `moveDown:` / `insertNewline:` / `cancelOperation:`.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    /// Changes whenever the panel is shown; triggers a re-focus.
    var focusToken: Int
    /// Whether the detail (full-content) view is currently open.
    var isExpanded: Bool
    var onMoveDown: () -> Void
    var onMoveUp: () -> Void
    var onMoveRight: () -> Void
    var onMoveLeft: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "Search clipboard…"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none          // no focus ring -> only the selected row reads as "focused"
        field.font = .systemFont(ofSize: 15)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Keep the coordinator's reference fresh so its delegate callbacks write
        // through the *current* binding/closures, not the ones captured at init.
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        // Re-focus whenever the panel is (re)shown.
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async { [weak field] in
                field?.window?.makeFirstResponder(field)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        var lastFocusToken = -1

        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // Detail (full-content) view is open: arrows/esc drive it, not the caret.
            if parent.isExpanded {
                switch selector {
                case #selector(NSResponder.moveLeft(_:)),
                     #selector(NSResponder.cancelOperation(_:)):
                    parent.onMoveLeft(); return true               // close detail
                case #selector(NSResponder.insertNewline(_:)):
                    parent.onSubmit(); return true                 // paste expanded item
                case #selector(NSResponder.moveUp(_:)),
                     #selector(NSResponder.moveDown(_:)),
                     #selector(NSResponder.moveRight(_:)):
                    return true                                     // swallow
                default:
                    return false                                    // typing collapses (via query change)
                }
            }

            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.moveRight(_:)):
                // Only hijack → when the caret is at the end of the query, so it
                // doesn't fight normal caret movement while editing the search.
                let length = (textView.string as NSString).length
                let range = textView.selectedRange()
                if range.length == 0 && range.location >= length {
                    parent.onMoveRight(); return true              // open detail
                }
                return false
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            default:
                return false
            }
        }
    }
}
