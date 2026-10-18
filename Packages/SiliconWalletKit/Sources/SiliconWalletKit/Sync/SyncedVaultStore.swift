import Foundation

/// A local change sync must send.
public enum SyncChange: Hashable, Sendable {
    case save(SyncItem)
    case delete(SyncItem)
}

/// Wraps the local store so every change `VaultSession` makes is reported to sync, without the
/// session knowing sync exists. Sync writes what it fetches to `base` directly, so remote
/// changes are never sent back.
@MainActor
public final class SyncedVaultStore: VaultStore {
    public let base: any SyncBackingStore
    /// Called after each local write, with what changed.
    public var onLocalChanges: (@MainActor ([SyncChange]) -> Void)?

    public init(base: any SyncBackingStore) {
        self.base = base
    }

    private func report(_ changes: [SyncChange]) {
        guard !changes.isEmpty else { return }
        onLocalChanges?(changes)
    }

    public func loadMeta() throws -> VaultMeta? { try base.loadMeta() }

    public func saveMeta(_ meta: VaultMeta) throws {
        try base.saveMeta(meta)
        report([.save(.meta)])
    }

    public func loadRecords() throws -> [SealedRecord] { try base.loadRecords() }

    public func saveRecords(_ records: [SealedRecord]) throws {
        try base.saveRecords(records)
        report(records.map { .save(.record($0.id)) })
    }

    public func deleteRecords(ids: [UUID]) throws {
        try base.deleteRecords(ids: ids)
        report(ids.map { .delete(.record($0)) })
    }

    public func loadAttachment(id: UUID) throws -> Data? { try base.loadAttachment(id: id) }

    public func saveAttachment(id: UUID, ciphertext: Data) throws {
        try base.saveAttachment(id: id, ciphertext: ciphertext)
        report([.save(.attachment(id))])
    }

    public func deleteAttachments(ids: [UUID]) throws {
        try base.deleteAttachments(ids: ids)
        report(ids.map { .delete(.attachment($0)) })
    }

    /// Deletes the vault on this device only. Its iCloud copy is untouched, so the next sync
    /// brings it back; deleting it everywhere is `VaultSync.deleteFromICloud()`.
    public func deleteAll() throws {
        try base.deleteAll()
    }
}
