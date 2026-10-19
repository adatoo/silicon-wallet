import SiliconWalletKit
import SwiftUI

/// The entries in the sidebar's scope, with search: a list in the middle column, or cards that
/// open the entry in a sheet (DESIGN.md §3).
struct EntryListView: View {
    @Environment(AppModel.self) private var model
    @Binding var editor: EditorTarget?
    @AppStorage(EntryListOptions.groupsByLetterKey) private var groupsByLetter = true
    @AppStorage(EntryListOptions.layoutKey) private var layout = EntryLayout.list
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        @Bindable var model = model
        let entries = model.visibleEntries
        Group {
            switch layout {
            case .list: list(entries)
            case .cards: cards(entries)
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
                EntryListOptions.Menu()
            }
            ToolbarItem {
                Button("New Entry", systemImage: "plus") { editor = .newEntry(groupID: model.selectedGroup?.id) }
                    .help("New entry")
                    .disabled(model.session?.groups.isEmpty != false)
            }
        }
    }

    private func list(_ entries: [VaultEntry]) -> some View {
        @Bindable var model = model
        return List(selection: $model.entrySelection) {
            if groupsByLetter {
                ForEach(entries.sectionedByFirstLetter()) { section in
                    Section(section.letter) {
                        ForEach(section.entries, content: row)
                    }
                    .sectionIndexLabel(section.letter)
                }
            } else {
                ForEach(entries, content: row)
            }
        }
        #if os(iOS)
            .listSectionIndexVisibility(groupsByLetter ? .visible : .hidden)
        #endif
    }

    private func row(_ entry: VaultEntry) -> some View {
        EntryRow(entry: entry, group: model.session?.group(id: entry.groupID))
            .tag(entry.id)
            .contextMenu { menuItems(for: entry) }
            .swipeActions {
                Button("Delete", systemImage: "trash", role: .destructive) { model.moveEntryToTrash(entry.id) }
            }
    }

    private func cards(_ entries: [VaultEntry]) -> some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 320), spacing: 14)], alignment: .leading,
                spacing: 14, pinnedViews: groupsByLetter ? [.sectionHeaders] : []
            ) {
                if groupsByLetter {
                    ForEach(entries.sectionedByFirstLetter()) { section in
                        Section {
                            ForEach(section.entries, content: card)
                        } header: {
                            Text(section.letter)
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                                .background(.background)
                        }
                    }
                } else {
                    ForEach(entries, content: card)
                }
            }
            .padding()
        }
    }

    private func card(_ entry: VaultEntry) -> some View {
        Button {
            model.openedEntry = OpenedEntry(id: entry.id)
        } label: {
            EntryCard(entry: entry, group: model.session?.group(id: entry.groupID))
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems(for: entry) }
    }

    @ViewBuilder
    private func menuItems(for entry: VaultEntry) -> some View {
        Button(entry.isFavorite ? "Remove from Favourites" : "Add to Favourites", systemImage: "star") {
            model.perform { try model.session?.setFavorite(!entry.isFavorite, entryID: entry.id) }
        }
        Button("Edit…", systemImage: "pencil") { editor = .entry(entry) }
        // Deleting moves the entry to Recently Deleted, so it needs no confirmation.
        Button("Delete", systemImage: "trash", role: .destructive) { model.moveEntryToTrash(entry.id) }
    }
}

/// How the entry list is shown. Kept in `UserDefaults`: these are display preferences, never
/// anything from the vault.
enum EntryListOptions {
    static let groupsByLetterKey = "groupsEntriesByLetter"
    static let layoutKey = "entryLayout"

    /// The entries column's View Options menu.
    struct Menu: View {
        @AppStorage(groupsByLetterKey) private var groupsByLetter = true
        @AppStorage(layoutKey) private var layout = EntryLayout.list

        var body: some View {
            SwiftUI.Menu("View Options", systemImage: "line.3.horizontal.decrease.circle") {
                Picker("View", selection: $layout) {
                    ForEach(EntryLayout.allCases, id: \.self) { layout in
                        Label(layout.title, systemImage: layout.symbol).tag(layout)
                    }
                }
                .pickerStyle(.inline)
                Toggle("Group by First Letter", isOn: $groupsByLetter)
            }
            .help("View options")
        }
    }
}

/// Entries as a list beside the detail column, or as cards that open in a sheet.
enum EntryLayout: String, CaseIterable {
    case list
    case cards

    var title: String {
        switch self {
        case .list: "as List"
        case .cards: "as Cards"
        }
    }

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .cards: "square.grid.2x2"
        }
    }
}

extension VaultEntry {
    /// The first non-concealed value, to tell similar entries apart, and whether its field is
    /// shown monospaced.
    func firstVisibleValue(in group: VaultGroup?) -> (text: String, isMonospaced: Bool)? {
        for field in group?.fields ?? [] where !field.isConcealed {
            if let value = values[field.id], !value.isEmpty { return (value, field.isMonospaced) }
        }
        return nil
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
                if let value = entry.firstVisibleValue(in: group) {
                    Text(value.text)
                        .font(.caption)
                        .fontDesign(value.isMonospaced ? .monospaced : nil)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let group {
                    Text(group.name)
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
}
