import Foundation
import Observation
import SiliconWalletKit
import SwiftUI

/// What the sidebar has selected.
enum SidebarItem: Hashable {
    case all
    case favorites
    case group(UUID)
}

/// An entry open in a sheet from the card view.
struct OpenedEntry: Identifiable, Hashable {
    let id: VaultEntry.ID
}

/// The app's state: the vault session plus what the UI has selected. Views only ever reach the
/// vault through `session` (DESIGN.md §3).
@MainActor
@Observable
final class AppModel {
    let session: VaultSession?
    /// iCloud sync, when this build can use it (DESIGN.md §7).
    let sync: VaultSync?
    /// Why the vault couldn't be opened at launch, if it couldn't.
    let startupError: String?

    var sidebarSelection: SidebarItem? = .all
    /// Which column a compact (iPhone) split view shows.
    var compactColumn = NavigationSplitViewColumn.sidebar
    var entrySelection: VaultEntry.ID?
    /// The entry open in a sheet, from the card view.
    var openedEntry: OpenedEntry?
    var searchText = ""
    /// Whether the Acrylic Wallet import sheet is showing.
    var isImportingAcrylic = false
    /// The message for the error alert; nil when none is showing.
    var errorMessage: String?

    init(session: VaultSession?, sync: VaultSync? = nil, startupError: String? = nil) {
        self.session = session
        self.sync = sync
        self.startupError = startupError
        if let session, let sync {
            sync.onRemoteChanges = { [weak session] in try? session?.reload() }
            sync.onVaultDeletedRemotely = { [weak session] in session?.vaultWasDeletedElsewhere() }
            sync.onConflict = { [weak session] losing in
                session?.keepConflictCopy(of: losing, deviceName: DeviceName.current)
            }
        }
    }

    /// The real vault in Application Support, or an in-memory one for UI tests and screenshots
    /// (launch argument `-InMemoryVault`, plus `-DemoVault` to fill it with fake entries).
    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        do {
            // Hosted unit tests run the app too; they must never touch a real vault.
            let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if arguments.contains("-InMemoryVault") || underTest {
                let session = try VaultSession(store: SwiftDataVaultStore.inMemory())
                return AppModel(session: session)
            }
            let directory = try SwiftDataVaultStore.defaultDirectory()
            let store = SyncedVaultStore(base: try SwiftDataVaultStore(directory: directory))
            let session = try VaultSession(store: store, accessLog: AccessLog(directory: directory))
            let sync =
                CloudEntitlement.isAvailable
                ? VaultSync(
                    store: store, containerIdentifier: CloudEntitlement.containerIdentifier,
                    stateURL: directory.appendingPathComponent("SyncState.json"))
                : nil
            return AppModel(session: session, sync: sync)
        } catch {
            return AppModel(session: nil, startupError: error.localizedDescription)
        }
    }

    /// Fills an in-memory vault with `DemoVault` when launched with `-DemoVault`.
    func prepareDemoIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) async {
        guard arguments.contains("-InMemoryVault"), arguments.contains("-DemoVault"), let session,
            session.state == .noVault
        else { return }
        do {
            try await DemoVault.fill(session)
            if arguments.contains("-Locked") { session.lock() }
            applyScreenshotArguments(arguments)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Picks the screen for App Store screenshots (`task screenshots`):
    /// `-ScreenshotSidebar favorites|<group name>`, `-ScreenshotEntry <title>`. With
    /// `-entryLayout cards` (which sets that preference for the launch) the entry opens in a sheet.
    private func applyScreenshotArguments(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        if let sidebar = value(after: "-ScreenshotSidebar") {
            if sidebar == "favorites" {
                sidebarSelection = .favorites
            } else if let group = session?.groups.first(where: { $0.name == sidebar }) {
                sidebarSelection = .group(group.id)
            }
            compactColumn = .content
        }
        if let title = value(after: "-ScreenshotEntry"),
            let entry = session?.entries.first(where: { $0.title == title })
        {
            if UserDefaults.standard.string(forKey: EntryListOptions.layoutKey) == EntryLayout.cards.rawValue {
                openedEntry = OpenedEntry(id: entry.id)
            } else {
                entrySelection = entry.id
            }
            compactColumn = .detail
        }
    }

    // MARK: - Derived lists

    var selectedGroup: VaultGroup? {
        guard case .group(let id) = sidebarSelection else { return nil }
        return session?.group(id: id)
    }

    /// The entries the middle column shows: the sidebar's scope, filtered by the search text.
    var visibleEntries: [VaultEntry] {
        guard let session else { return [] }
        let scoped: [VaultEntry]
        switch sidebarSelection ?? .all {
        case .all: scoped = session.search(searchText)
        case .favorites: scoped = session.search(searchText).filter(\.isFavorite)
        case .group(let id): scoped = session.search(searchText, inGroup: id)
        }
        return scoped
    }

    var selectedEntry: VaultEntry? {
        entrySelection.flatMap { session?.entry(id: $0) }
    }

    func title(for item: SidebarItem) -> String {
        switch item {
        case .all: "All Entries"
        case .favorites: "Favourites"
        case .group(let id): session?.group(id: id)?.name ?? "Group"
        }
    }

    // MARK: - Actions

    /// Runs a vault change, turning any error into the alert.
    func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func lock() {
        entrySelection = nil
        openedEntry = nil
        searchText = ""
        session?.lock()
    }

    func deleteGroup(_ id: UUID) {
        perform { try session?.deleteGroup(id: id) }
        if sidebarSelection == .group(id) { sidebarSelection = .all }
        if let entrySelection, session?.entry(id: entrySelection) == nil { self.entrySelection = nil }
    }

    func deleteEntry(_ id: UUID) {
        perform { try session?.deleteEntry(id: id) }
        if entrySelection == id { entrySelection = nil }
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case VaultError.wrongPassword: "That password is wrong."
        case VaultError.locked: "The vault is locked."
        case VaultError.notFound: "That item no longer exists."
        case VaultError.unknownGroup: "Choose a group for this entry."
        case VaultError.attachmentUnavailable: "This attachment isn't on this device yet."
        case VaultError.attachmentCorrupt: "This attachment is damaged and can't be opened."
        case VaultError.unsupportedFormat:
            "This vault was made by a newer version of Silicon Wallet. Update the app to open it."
        default: error.localizedDescription
        }
    }
}
