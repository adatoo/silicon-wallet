import SwiftUI

#if os(iOS)
    /// Sync, Lock, Settings and Help on iOS. iPad shows them at the top right of the entries
    /// column, where there's room; iPhone shows them above the groups list (DESIGN.md §3).
    struct VaultActionsToolbar: ToolbarContent {
        @Environment(AppModel.self) private var model
        @Environment(LockController.self) private var lock
        var placement: ToolbarItemPlacement = .topBarTrailing

        var body: some ToolbarContent {
            ToolbarItemGroup(placement: placement) {
                if let sync = model.sync {
                    SyncStatusButton(sync: sync)
                }
                Button("Lock", systemImage: "lock") { lock.lockNow() }
                SettingsButton()
                HelpButton(systemImage: "questionmark.circle")
            }
        }
    }
#endif
