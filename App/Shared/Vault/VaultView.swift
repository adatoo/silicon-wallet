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
    @AppStorage(EntryListOptions.layoutKey) private var layout = EntryLayout.list

    var body: some View {
        @Bindable var model = model
        Group {
            switch layout {
            case .list:
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $model.compactColumn) {
                    sidebar
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
            case .cards:
                // Cards take the width the detail column would have; an entry opens in a sheet.
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: cardsCompactColumn) {
                    sidebar
                } detail: {
                    EntryListView(editor: $editor)
                }
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
        .sheet(item: $editor) { EditorSheet(target: $0) }
        .sheet(item: $model.openedEntry) { EntrySheet(entryID: $0.id) }
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

    private var sidebar: some View {
        SidebarView(editor: $editor)
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }

    /// `AppModel.compactColumn` is in the list layout's terms; with two columns its entries
    /// column is the detail column.
    private var cardsCompactColumn: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { model.compactColumn == .content ? .detail : model.compactColumn },
            set: { model.compactColumn = $0 == .detail ? .content : $0 }
        )
    }

    private func newEntry() {
        editor = .newEntry(groupID: model.selectedGroup?.id)
    }
}

/// Creates or edits a group or entry, in a sheet.
struct EditorSheet: View {
    let target: EditorTarget

    var body: some View {
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
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif
    @AppStorage(EntryListOptions.groupsByLetterKey) private var groupsByLetter = true
    @AppStorage(EntryListOptions.layoutKey) private var layout = EntryLayout.list

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
            ForEach(Array(EntryLayout.allCases.enumerated()), id: \.element) { index, option in
                Toggle(option.title, isOn: Binding(get: { layout == option }, set: { if $0 { layout = option } }))
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Toggle("Group by First Letter", isOn: $groupsByLetter)
            Divider()
        }
        CommandMenu("Vault") {
            Button("Lock") { lock.lockNow() }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(model.session?.isUnlocked != true)
        }
        #if os(macOS)
            CommandGroup(replacing: .help) {
                Button("Silicon Wallet Help") { openWindow(id: HelpView.windowID) }
                    .keyboardShortcut("?")
            }
        #endif
    }
}
