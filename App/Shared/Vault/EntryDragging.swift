import SiliconWalletKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// An entry being dragged onto a group. Declared in `project.yml`.
    static let draggedEntry = UTType(exportedAs: "com.datoos.silicon-wallet.entry")
}

/// What a dragged entry puts on the drag pasteboard: its ID only, never vault data, so dropping
/// it in another app gives that app nothing.
struct DraggedEntry: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .draggedEntry)
    }
}

/// What follows the pointer while an entry is dragged: its group's icon and its title, never a value.
struct DraggedEntryPreview: View {
    let entry: VaultEntry
    let group: VaultGroup?

    var body: some View {
        Label {
            Text(entry.title.isEmpty ? "Untitled" : entry.title)
                .lineLimit(1)
        } icon: {
            GroupSymbol(group?.icon)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: .capsule)
    }
}
