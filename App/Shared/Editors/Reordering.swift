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
    /// handle on the right, and dropping the row on another puts it there; a Mac form ignores
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
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        #if os(macOS)
            HStack(spacing: 10) {
                content
                DragHandle(row: ReorderedRow(id: id), title: title)
            }
            .dropDestination(for: ReorderedRow.self) { rows, _ in
                move(rows.first?.id)
            } isTargeted: {
                isTargeted = $0
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
        #else
            content
        #endif
    }

    /// Puts the dropped row where this one is: after it when moving down, before it when moving up.
    private func move(_ droppedID: UUID?) -> Bool {
        guard let from = items.firstIndex(where: { $0.id == droppedID }),
            let to = items.firstIndex(where: { $0.id == id }), from != to
        else { return false }
        items.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
        return true
    }
}

#if os(macOS)
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
                .draggable(row) {
                    Label(title.isEmpty ? "Untitled" : title, systemImage: "line.3.horizontal")
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 6))
                }
        }
    }
#endif
