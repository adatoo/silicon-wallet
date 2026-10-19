import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// A row of an editor's list being dragged to a new place. Declared in `project.yml`.
    static let reorderedRow = UTType(exportedAs: "com.datoos.silicon-wallet.reordered-row")
}

/// What a dragged row puts on the drag pasteboard: its ID only, never vault data.
struct ReorderedRow: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .reorderedRow)
    }
}

extension View {
    /// Lets this row of an editor's list be dragged to a new place in `items`. On the Mac it adds a
    /// handle on the right, and the other rows make room as it is dragged; a Mac form ignores
    /// `onMove`. iOS reorders with `onMove` and edit mode instead, so this changes nothing there.
    func reorderable<Item: Identifiable>(_ item: Item, in items: Binding<[Item]>, title: String) -> some View
    where Item.ID == UUID {
        modifier(Reorderable(id: item.id, items: items, title: title))
    }
}

private struct Reorderable<Item: Identifiable>: ViewModifier where Item.ID == UUID {
    let id: UUID
    @Binding var items: [Item]
    let title: String

    func body(content: Content) -> some View {
        #if os(macOS)
            // An overlay, not an HStack: in an HStack a wrapping text field in the row is laid out
            // one line high, so a long value scrolls instead of growing.
            // The row fills the width, so the handle sits at its right edge however narrow the
            // row's content is.
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 30)
                .overlay(alignment: .trailing) {
                    DragHandle(row: ReorderedRow(id: id), title: title)
                }
                .opacity(ReorderDrag.shared.id == id ? 0.4 : 1)
                .dropDestination(for: ReorderedRow.self) { rows, _ in
                    ReorderDrag.shared.id = nil
                    guard let droppedID = rows.first?.id, items.contains(where: { $0.id == droppedID }) else {
                        return false
                    }
                    withAnimation(.snappy) { move(droppedID) }
                    return true
                } isTargeted: { isTargeted in
                    // The rows make room as the dragged one passes, as they do on iOS.
                    if isTargeted, let draggedID = ReorderDrag.shared.id {
                        withAnimation(.snappy) { move(draggedID) }
                    }
                }
        #else
            content
        #endif
    }

    /// Puts the dragged row where this one is: after it when moving down, before it when moving up.
    private func move(_ draggedID: UUID) {
        guard let from = items.firstIndex(where: { $0.id == draggedID }),
            let to = items.firstIndex(where: { $0.id == id }), from != to
        else { return }
        items.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
    }
}

#if os(macOS)
    /// The row being dragged, so the rows it passes over can make room for it before the drop.
    @MainActor @Observable
    private final class ReorderDrag {
        static let shared = ReorderDrag()
        var id: UUID?
    }

    /// Where to grab a row to drag it, in its own column on the right of the row.
    private struct DragHandle: View {
        let row: ReorderedRow
        let title: String

        var body: some View {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 24)
                .contentShape(.rect)
                .pointerStyle(.grabIdle)
                .help("Drag to reorder")
                .accessibilityHidden(true)
                .draggable(begin()) {
                    Label(title.isEmpty ? "Untitled" : title, systemImage: "line.3.horizontal")
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 6))
                }
                .onDragSessionUpdated { session in
                    if case .ended = session.phase { ReorderDrag.shared.id = nil }
                }
        }

        /// Called when the drag starts, which is when `draggable` asks for its payload.
        private func begin() -> ReorderedRow {
            ReorderDrag.shared.id = row.id
            return row
        }
    }
#endif
