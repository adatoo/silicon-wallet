import SiliconWalletKit
import SwiftUI

/// What a sheet is editing.
enum EditorTarget: Identifiable {
    case newGroup
    case group(VaultGroup)
    case newEntry(groupID: UUID?)
    case entry(VaultEntry)

    var id: String {
        switch self {
        case .newGroup: "new-group"
        case .group(let group): "group-\(group.id)"
        case .newEntry: "new-entry"
        case .entry(let entry): "entry-\(entry.id)"
        }
    }
}

/// The unlocked vault: Groups | Entries | Detail (DESIGN.md §3).
struct VaultView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: EditorTarget?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(editor: $editor)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } content: {
            EntryListView(editor: $editor)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 480)
        } detail: {
            if let entry = model.selectedEntry {
                EntryDetailView(entry: entry, editor: $editor)
                    .id(entry.id)
            } else {
                ContentUnavailableView("No Entry Selected", systemImage: "key.horizontal")
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Lock", systemImage: "lock") { model.lock() }
                    .help("Lock the vault")
            }
        }
        .sheet(item: $editor) { target in
            NavigationStack {
                switch target {
                case .newGroup: GroupEditorView(group: nil)
                case .group(let group): GroupEditorView(group: group)
                case .newEntry(let groupID): EntryEditorView(entry: nil, preferredGroupID: groupID)
                case .entry(let entry): EntryEditorView(entry: entry, preferredGroupID: entry.groupID)
                }
            }
            #if os(macOS)
                .frame(minWidth: 480, idealWidth: 540, minHeight: 480, idealHeight: 620)
            #endif
        }
        .focusedSceneValue(\.vaultActions, VaultActions(newEntry: newEntry, newGroup: { editor = .newGroup }))
        .onChange(of: model.session?.unreadableRecordCount) { _, count in
            if let count, count > 0 {
                model.errorMessage =
                    "\(count) item\(count == 1 ? "" : "s") in this vault couldn't be opened. They may be damaged, or were changed outside Silicon Wallet."
            }
        }
    }

    private func newEntry() {
        editor = .newEntry(groupID: model.selectedGroup?.id)
    }
}

/// Menu and keyboard commands for the focused vault window.
struct VaultActions {
    var newEntry: () -> Void
    var newGroup: () -> Void
}

extension FocusedValues {
    @Entry var vaultActions: VaultActions?
}

struct VaultCommands: Commands {
    let model: AppModel
    @FocusedValue(\.vaultActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { actions?.newEntry() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("New Group") { actions?.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandMenu("Vault") {
            Button("Lock") { model.lock() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(model.session?.isUnlocked != true)
        }
    }
}
