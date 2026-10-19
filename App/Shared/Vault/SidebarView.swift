import SiliconWalletKit
import SwiftUI

/// The first column: All Entries, Favourites, the groups, then Recently Deleted when it has
/// anything in it.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Binding var editor: EditorTarget?
    @State private var groupToDelete: VaultGroup?
    /// iOS: show Sync, Lock, Settings and Help here. VaultView decides, from the window's
    /// size class: an iPad's sidebar column reports compact even when the window is regular.
    var showsVaultActions = false

    var body: some View {
        @Bindable var model = model
        let session = model.session
        List(selection: $model.sidebarSelection) {
            Section {
                Label("All Entries", systemImage: "tray.full")
                    .badge(session?.entries.count ?? 0)
                    .tag(SidebarItem.all)
                Label("Favourites", systemImage: "star")
                    .badge(session?.favorites.count ?? 0)
                    .tag(SidebarItem.favorites)
            }
            Section("Groups") {
                ForEach(session?.groups ?? []) { group in
                    Label(group.name, systemImage: group.icon)
                        .badge(session?.entries(inGroup: group.id).count ?? 0)
                        .tag(SidebarItem.group(group.id))
                        .contextMenu {
                            Button("Edit Group…", systemImage: "pencil") { editor = .group(group) }
                            Button("Delete Group…", systemImage: "trash", role: .destructive) { groupToDelete = group }
                        }
                }
                .onMove(perform: move)
            }
            if let session, !model.isTrashEmpty {
                Section {
                    Label("Recently Deleted", systemImage: "trash")
                        .badge(session.deletedGroups.count + session.deletedEntries.count)
                        .tag(SidebarItem.recentlyDeleted)
                }
            }
        }
        .onChange(of: model.isTrashEmpty) { model.dropStaleSelection() }
        .navigationTitle("Silicon Wallet")
        .toolbar {
            ToolbarItem {
                Button("New Group", systemImage: "folder.badge.plus") { editor = .newGroup }
                    .help("New group")
            }
            #if os(iOS)
                if showsVaultActions {
                    VaultActionsToolbar(placement: .topBarLeading)
                }
            #endif
        }
        .confirmationDialog(
            "Delete \(groupToDelete?.name ?? "this group")?", isPresented: deleteBinding, titleVisibility: .visible,
            presenting: groupToDelete
        ) { group in
            Button("Delete Group", role: .destructive) { model.moveGroupToTrash(group.id) }
        } message: { group in
            let count = session?.entries(inGroup: group.id).count ?? 0
            Text(
                count == 0
                    ? "It moves to Recently Deleted, where you can recover it for 30 days."
                    : "It moves to Recently Deleted with its \(count) entr\(count == 1 ? "y" : "ies"), where you can recover them for 30 days."
            )
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } })
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let session = model.session else { return }
        var ids = session.groups.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        model.perform { try session.reorderGroups(ids) }
    }
}
