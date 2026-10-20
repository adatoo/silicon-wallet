import SiliconWalletKit
import SwiftUI

/// The entries column while the sidebar shows Recently Deleted: deleted groups and entries, each
/// with how long it has left, to recover or delete for good (DESIGN.md §5). Always a list, in
/// both layouts; in the card layout an entry opens in the entry sheet.
struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(EntryListOptions.layoutKey) private var layout = EntryLayout.list
    @State private var toDelete: Item?
    @State private var confirmingDeleteAll = false

    /// Something in Recently Deleted that can be deleted for good.
    enum Item: Identifiable {
        case group(VaultGroup)
        case entry(VaultEntry)

        var id: UUID {
            switch self {
            case .group(let group): group.id
            case .entry(let entry): entry.id
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        let groups = visibleGroups
        let entries = model.visibleEntries
        List(selection: layout == .list ? $model.entrySelection : .constant(nil)) {
            if !groups.isEmpty {
                Section("Groups") {
                    ForEach(groups, content: groupRow)
                }
            }
            if !entries.isEmpty {
                Section("Entries") {
                    ForEach(entries, content: entryRow)
                }
            }
            if !groups.isEmpty || !entries.isEmpty {
                Section {
                } footer: {
                    Text("Items are deleted for good 30 days after you delete them.")
                }
            }
        }
        .overlay {
            if groups.isEmpty && entries.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView(
                        "No Recently Deleted Items", systemImage: "trash",
                        description: Text("Deleted entries and groups stay here for 30 days."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "Search")
        .navigationTitle("Recently Deleted")
        .toolbar {
            ToolbarItem {
                Button("Delete All…", systemImage: "trash.slash") { confirmingDeleteAll = true }
                    .help("Delete everything in Recently Deleted for good")
                    .disabled(model.isTrashEmpty)
            }
        }
        .confirmationDialog(
            deleteTitle, isPresented: deleteBinding, titleVisibility: .visible, presenting: toDelete
        ) { item in
            Button("Delete Now", role: .destructive) {
                switch item {
                case .group(let group): model.deleteGroupPermanently(group.id)
                case .entry(let entry): model.deleteEntryPermanently(entry.id)
                }
            }
        } message: { item in
            Text(deleteMessage(for: item))
        }
        .confirmationDialog(
            "Delete Everything in Recently Deleted?", isPresented: $confirmingDeleteAll, titleVisibility: .visible
        ) {
            Button("Delete All", role: .destructive) { model.emptyTrash() }
        } message: {
            let count = (model.session?.deletedGroups.count ?? 0) + (model.session?.deletedEntries.count ?? 0)
            Text(
                "\(count) item\(count == 1 ? "" : "s") will be deleted from this vault on all your devices. This can't be undone."
            )
        }
    }

    /// Deleted groups whose names match the search, if there is one.
    private var visibleGroups: [VaultGroup] {
        let groups = model.session?.deletedGroups ?? []
        let words = model.searchText.split(whereSeparator: \.isWhitespace)
        return groups.filter { group in
            words.allSatisfy { group.name.localizedStandardContains($0) }
        }
    }

    private func groupRow(_ group: VaultGroup) -> some View {
        let count =
            model.session?.deletedEntries.filter { $0.groupID == group.id && $0.deleted == group.deleted }
            .count ?? 0
        return TrashRow(
            title: group.name.isEmpty ? "Untitled" : group.name, icon: group.icon,
            detail: "\(count) entr\(count == 1 ? "y" : "ies")", purgeDate: purgeDate(group.id, group.deleted)
        )
        .contextMenu { actions(.group(group)) }
        .swipeActions { actions(.group(group)) }
    }

    @ViewBuilder
    private func entryRow(_ entry: VaultEntry) -> some View {
        let group = model.session?.group(id: entry.groupID) ?? model.session?.deletedGroup(id: entry.groupID)
        let row = TrashRow(
            title: entry.title.isEmpty ? "Untitled" : entry.title, icon: group?.icon ?? "questionmark.folder",
            detail: group?.name ?? "No group", purgeDate: purgeDate(entry.id, entry.deleted))
        Group {
            if layout == .cards {
                Button {
                    model.openedEntry = OpenedEntry(id: entry.id)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            } else {
                row.tag(entry.id)
            }
        }
        .contextMenu { actions(.entry(entry)) }
        .swipeActions { actions(.entry(entry)) }
    }

    private func purgeDate(_ id: UUID, _ deleted: Date?) -> Date? {
        deleted.flatMap { model.session?.purgeDate(forTrashedItem: id, deletedAt: $0) }
    }

    @ViewBuilder
    private func actions(_ item: Item) -> some View {
        Button("Recover", systemImage: "arrow.uturn.backward") {
            switch item {
            case .group(let group): model.restoreGroup(group.id)
            case .entry(let entry): model.restoreEntry(entry.id)
            }
        }
        .tint(.accentColor)
        Button("Delete Now…", systemImage: "trash", role: .destructive) { toDelete = item }
    }

    private var deleteTitle: String {
        switch toDelete {
        case .group(let group): "Delete \(group.name) Now?"
        case .entry(let entry): "Delete \(entry.title) Now?"
        case nil: "Delete Now?"
        }
    }

    private func deleteMessage(for item: Item) -> String {
        switch item {
        case .group(let group):
            let count = model.session?.deletedEntries.filter { $0.groupID == group.id }.count ?? 0
            return count == 0
                ? "It will be deleted from this vault on all your devices. This can't be undone."
                : "It will be deleted, with its \(count) entr\(count == 1 ? "y" : "ies") in Recently Deleted, from this vault on all your devices. This can't be undone."
        case .entry:
            return "It will be deleted from this vault on all your devices, with its attachments. This can't be undone."
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })
    }
}

/// A deleted group or entry: its name, what it belongs to, and how long until it's deleted for
/// good.
struct TrashRow: View {
    let title: String
    let icon: String
    let detail: String
    let purgeDate: Date?

    var body: some View {
        HStack(spacing: 10) {
            GroupSymbol(icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text("\(detail) · \(TrashRow.timeLeft(until: purgeDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// "12 days left", until the item is deleted for good.
    static func timeLeft(until purgeDate: Date?, now: Date = .now) -> String {
        guard let purgeDate else { return "" }
        let remaining = purgeDate.timeIntervalSince(now)
        let days = Int((remaining / (24 * 60 * 60)).rounded(.up))
        return days <= 1 ? "Less than a day left" : "\(days) days left"
    }
}
