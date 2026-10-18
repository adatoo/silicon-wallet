import SiliconWalletKit
import SwiftUI

/// The middle column: the entries in the sidebar's scope, with search.
struct EntryListView: View {
    @Environment(AppModel.self) private var model
    @Binding var editor: EditorTarget?
    @State private var entryToDelete: VaultEntry?
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        @Bindable var model = model
        let entries = model.visibleEntries
        List(selection: $model.entrySelection) {
            ForEach(entries) { entry in
                EntryRow(entry: entry, group: model.session?.group(id: entry.groupID))
                    .tag(entry.id)
                    .contextMenu {
                        Button(entry.isFavorite ? "Remove from Favourites" : "Add to Favourites", systemImage: "star") {
                            model.perform { try model.session?.setFavorite(!entry.isFavorite, entryID: entry.id) }
                        }
                        Button("Edit…", systemImage: "pencil") { editor = .entry(entry) }
                        Button("Delete…", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { entryToDelete = entry }
                    }
            }
        }
        .overlay {
            if entries.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Entries", systemImage: "tray")
                    } description: {
                        Text("Add an entry to keep a password, card or note safe.")
                    } actions: {
                        Button("New Entry") { editor = .newEntry(groupID: model.selectedGroup?.id) }
                            .disabled(model.session?.groups.isEmpty != false)
                        if model.session?.entries.isEmpty == true {
                            Button("Import from Acrylic Wallet…") { model.isImportingAcrylic = true }
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "Search")
        .navigationTitle(model.title(for: model.sidebarSelection ?? .all))
        #if os(iOS)
            // A compact split view's content column drops its large title, so show it inline.
            .toolbarTitleDisplayMode(horizontalSizeClass == .compact ? .inline : .automatic)
        #endif
        .toolbar {
            ToolbarItem {
                Button("New Entry", systemImage: "plus") { editor = .newEntry(groupID: model.selectedGroup?.id) }
                    .help("New entry")
                    .disabled(model.session?.groups.isEmpty != false)
            }
        }
        .confirmationDialog(
            "Delete \(entryToDelete?.title ?? "this entry")?", isPresented: deleteBinding, titleVisibility: .visible,
            presenting: entryToDelete
        ) { entry in
            Button("Delete Entry", role: .destructive) { model.deleteEntry(entry.id) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { entryToDelete != nil }, set: { if !$0 { entryToDelete = nil } })
    }
}

struct EntryRow: View {
    let entry: VaultEntry
    let group: VaultGroup?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: group?.icon ?? "questionmark.folder")
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title.isEmpty ? "Untitled" : entry.title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if entry.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .imageScale(.small)
                    .accessibilityLabel("Favourite")
            }
        }
        .padding(.vertical, 2)
    }

    /// The first non-concealed value, to tell similar entries apart.
    private var subtitle: String? {
        for field in group?.fields ?? [] where !field.isConcealed {
            if let value = entry.values[field.id], !value.isEmpty { return value }
        }
        return group?.name
    }
}
