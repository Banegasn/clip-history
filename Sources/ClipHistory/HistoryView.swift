import SwiftUI
import AppKit

/// The searchable clipboard-history list shown in the floating panel.
/// Type to filter, ↑/↓ to move, → to expand full content (← / Esc to go back),
/// ⌘⌫ to delete the selection, Return to paste, Esc to dismiss, click to paste.
struct HistoryView: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if let expanded = model.expandedItem {
                DetailView(item: expanded, model: model)
            } else {
                list
            }
        }
        .frame(width: 540, height: 460)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { model.selection = 0 }
        .onChange(of: model.query) { _, _ in
            model.selection = 0
            model.expandedItem = nil   // typing returns to the (filtered) list
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            SearchField(
                text: $model.query,
                focusToken: model.focusRequest,
                isExpanded: model.expandedItem != nil,
                onMoveDown: { model.move(1) },
                onMoveUp: { model.move(-1) },
                onMoveRight: { model.expandSelected() },
                onMoveLeft: { model.collapse() },
                onDeleteEntry: { model.deleteSelected() },
                onSubmit: { model.pickSelected() },
                onCancel: { model.onClose() }
            )
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    let items = model.filtered
                    if items.isEmpty {
                        Text(model.query.isEmpty ? "Clipboard history is empty" : "No matches")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 48)
                    } else {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            RowView(item: item, selected: index == model.selection)
                                // Identity = item.id, consistent with the ForEach.
                                // (A previous `.id(index)` collided with the
                                // element-id identity and made the highlight land
                                // on the wrong row vs. what Enter actually pasted.)
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.pick(at: index) }
                        }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, newValue in
                let f = model.filtered
                guard f.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(f[newValue].id, anchor: .center)
                }
            }
        }
    }
}

private struct RowView: View {
    let item: ClipItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {                       // .center: trailing aligns with text
            thumbnail
                .frame(width: 28, height: 28)
            Text(item.displayText.isEmpty ? "(empty)" : item.displayText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            // Type label + expand chevron, vertically centered, on every row.
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.85) : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb = item.thumb, let nsImage = NSImage(data: thumb) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(selected ? Color.white : Color.secondary)
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .file: return "doc"
        case .image: return "photo"
        }
    }

    private var label: String {
        switch item.kind {
        case .text: return "TEXT"
        case .file: return "FILE"
        case .image: return "IMAGE"
        }
    }
}

/// Full-content view shown when the user presses → on a selection.
/// ← or Esc returns to the list; Enter still pastes.
private struct DetailView: View {
    let item: ClipItem
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                Spacer()
                Text("← / Esc · Enter to paste")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            if let link = item.link {
                Divider()
                HStack(spacing: 10) {
                    Button {
                        NSWorkspace.shared.open(link)
                        model.onClose()
                    } label: {
                        Label("Open Link", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Text(link.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .image, let thumb = item.thumb, let nsImage = NSImage(data: thumb) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
        } else {
            Text(item.text ?? "")
                .font(.system(size: 13, design: item.kind == .file ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
