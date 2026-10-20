import Foundation

/// The CloudKit environment a build syncs with. Development builds use Development; TestFlight
/// and App Store builds use Production, which starts empty (DESIGN.md §7). Each keeps its own
/// engine state, so moving a device from one to the other uploads the vault afresh.
public enum CloudEnvironment: Sendable {
    case development
    case production

    /// The file, in the vault folder, that holds `CKSyncEngine`'s state for this environment.
    /// Development keeps the name every earlier build used.
    public var stateFileName: String {
        switch self {
        case .development: "SyncState.json"
        case .production: "SyncState-Production.json"
        }
    }
}
