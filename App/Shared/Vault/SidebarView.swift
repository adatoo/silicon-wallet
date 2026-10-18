import SiliconWalletKit
import SwiftUI

/// The first column: All Entries, Favourites, then the groups.
struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockController.self) private var lock
    @Binding var editor: EditorTarget?
    @State private var groupToDelete: VaultGroup?
    @State private var showingSettings = false

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
        }
        .navigationTitle("Silicon Wallet")
        .toolbar {
            ToolbarItem {
                Button("New Group", systemImage: "folder.badge.plus") { editor = .newGroup }
                    .help("New group")
            }
            #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gear") { showingSettings = true }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Lock", systemImage: "lock") { lock.lockNow() }
                }
                if let sync = model.sync {
                    ToolbarItem(placement: .topBarTrailing) { SyncStatusButton(sync: sync) }
                }
            #endif
        }
        #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
        #endif
        .confirmationDialog(
            "Delete \(groupToDelete?.name ?? "this group")?", isPresented: deleteBinding, titleVisibility: .visible,
            presenting: groupToDelete
        ) { group in
            Button("Delete Group and Entries", role: .destructive) { model.deleteGroup(group.id) }
        } message: { group in
            let count = session?.entries(inGroup: group.id).count ?? 0
            Text(
                count == 0
                    ? "This can't be undone."
                    : "Its \(count) entr\(count == 1 ? "y" : "ies") will be deleted too. This can't be undone.")
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
