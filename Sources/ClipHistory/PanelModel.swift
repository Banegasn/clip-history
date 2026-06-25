import SwiftUI

/// Observable state shared between the SwiftUI panel view and its controller.
final class PanelModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Bumped each time the panel is shown so the search field re-grabs focus.
    @Published var focusRequest: Int = 0
    /// When non-nil, the panel shows the full content of this item (→ to open).
    @Published var expandedItem: ClipItem?

    /// The controller wires these to perform the actual paste / dismiss / delete.
    var onPick: (ClipItem) -> Void = { _ in }
    var onClose: () -> Void = {}
    /// Remove an item from the persistent store (and refresh `items`).
    var onDelete: (ClipItem) -> Void = { _ in }

    var filtered: [ClipItem] {
        guard !query.isEmpty else { return items }
        let q = query.lowercased()
        return items.filter { $0.searchText.contains(q) }
    }

    func move(_ delta: Int) {
        let count = filtered.count
        guard count > 0 else { return }
        selection = min(max(0, selection + delta), count - 1)
    }

    func pick(at index: Int) {
        let list = filtered
        guard list.indices.contains(index) else { return }
        onPick(list[index])
    }

    func pickSelected() {
        if let item = expandedItem {
            onPick(item)
            return
        }
        pick(at: selection)
    }

    /// Open the full-content detail view for the current selection.
    func expandSelected() {
        let list = filtered
        guard list.indices.contains(selection) else { return }
        expandedItem = list[selection]
    }

    func collapse() {
        expandedItem = nil
    }

    /// Delete the current selection from history, then keep the selection valid.
    func deleteSelected() {
        let list = filtered
        guard list.indices.contains(selection) else { return }
        onDelete(list[selection])          // store delete + refresh of `items`
        let count = filtered.count
        selection = count == 0 ? 0 : min(selection, count - 1)
    }
}
