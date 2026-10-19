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
    @Environment(LockController.self) private var lock
    @State private var editor: EditorTarget?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $model.compactColumn) {
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
        #if os(macOS)
            .toolbar {
                if let sync = model.sync {
                    ToolbarItem(placement: .primaryAction) { SyncStatusButton(sync: sync) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Lock", systemImage: "lock") { lock.lockNow() }
                    .help("Lock the vault")
                }
            }
        #endif
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
        .sheet(isPresented: $model.isImportingAcrylic) {
            NavigationStack { AcrylicImportView() }
        }
        .focusedSceneValue(
            \.vaultActions,
            VaultActions(
                newEntry: newEntry, newGroup: { editor = .newGroup },
                importAcrylic: { model.isImportingAcrylic = true })
        )
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
    var importAcrylic: () -> Void
}

extension FocusedValues {
    @Entry var vaultActions: VaultActions?
}

struct VaultCommands: Commands {
    let model: AppModel
    let lock: LockController
    @FocusedValue(\.vaultActions) private var actions
    @AppStorage(EntryListOptions.groupsByLetterKey) private var groupsByLetter = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Entry") { actions?.newEntry() }
                .keyboardShortcut("n")
                .disabled(actions == nil)
            Button("New Group") { actions?.newGroup() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Import from Acrylic Wallet…") { actions?.importAcrylic() }
                .disabled(actions == nil)
        }
        CommandGroup(before: .toolbar) {
            Toggle("Group by First Letter", isOn: $groupsByLetter)
            Divider()
        }
        CommandMenu("Vault") {
            Button("Lock") { lock.lockNow() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(model.session?.isUnlocked != true)
        }
    }
}
