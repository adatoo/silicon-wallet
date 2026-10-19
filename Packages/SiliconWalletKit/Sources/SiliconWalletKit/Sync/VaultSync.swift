import CloudKit
import Foundation
import Observation

/// Syncs the vault through `CKSyncEngine` against the private CloudKit database, in the zone
/// `Vault` (DESIGN.md §7, ADR-0004). Everything sent is already sealed; CloudKit never sees
/// plaintext.
@MainActor
@Observable
public final class VaultSync: CKSyncEngineDelegate {
    public enum Status: Equatable, Sendable {
        case starting
        case idle(lastSync: Date?)
        case syncing
        /// No iCloud account, or iCloud Drive is off. Local data is kept; sync waits.
        case noAccount
        case failed(String)
    }

    public private(set) var status = Status.starting
    /// True once the first fetch has finished (or failed), so first-run setup knows whether
    /// iCloud already has a vault.
    public private(set) var hasCompletedFirstFetch = false

    /// Called after fetched changes are written locally, so the session can reload.
    @ObservationIgnored public var onRemoteChanges: (@MainActor () -> Void)?
    /// Called with the local version of a record that lost a conflict, so the session can keep
    /// it as a conflict copy (DESIGN.md §7).
    @ObservationIgnored public var onConflict: (@MainActor (SealedRecord) -> Void)?
    /// Called when the vault was deleted in iCloud on purpose (from another device, or from
    /// iCloud settings), after the local copy has been removed too.
    @ObservationIgnored public var onVaultDeletedRemotely: (@MainActor () -> Void)?
    /// Whether to take a fetched group or entry in place of the local copy. The session refuses
    /// one it can't open while it can open the local copy, so a damaged or tampered server copy
    /// can't destroy a good one; the local copy is then sent back over it.
    @ObservationIgnored public var acceptsIncomingRecord: (@MainActor (SealedRecord) -> Bool)?

    @ObservationIgnored private let store: SyncedVaultStore
    @ObservationIgnored private var base: any SyncBackingStore { store.base }
    @ObservationIgnored private let containerIdentifier: String
    @ObservationIgnored private let stateURL: URL
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var lastSync: Date?

    public init(store: SyncedVaultStore, containerIdentifier: String, stateURL: URL) {
        self.store = store
        self.containerIdentifier = containerIdentifier
        self.stateURL = stateURL
    }

    /// Starts the engine and begins queuing local changes. Call once.
    public func start() {
        guard engine == nil else { return }
        let container = CKContainer(identifier: containerIdentifier)
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: loadState(), delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine

        store.onLocalChanges = { [weak self] changes in self?.enqueue(changes) }
        if engine.state.pendingDatabaseChanges.isEmpty, loadState() == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecordMapping.zoneID))])
            enqueue(((try? base.allSyncItems()) ?? []).map { .save($0) })
        }
        Task { await syncNow() }
    }

    /// Fetches, then sends, now rather than when the engine next decides to.
    public func syncNow() async {
        guard let engine else { return }
        status = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            lastSync = .now
            status = .idle(lastSync: lastSync)
        } catch let error as CKError
            where error.code == .notAuthenticated || error.code == .accountTemporarilyUnavailable
        {
            status = .noAccount
        } catch {
            status = .failed(error.localizedDescription)
        }
        hasCompletedFirstFetch = true
    }

    /// Deletes the vault's zone from iCloud: every synced record on every device's next sync.
    public func deleteFromICloud() async throws {
        guard let engine else { return }
        engine.state.remove(pendingRecordZoneChanges: engine.state.pendingRecordZoneChanges)
        engine.state.add(pendingDatabaseChanges: [.deleteZone(SyncRecordMapping.zoneID)])
        try await engine.sendChanges()
    }

    private func reuploadEverything(_ engine: CKSyncEngine) {
        let items = (try? base.allSyncItems()) ?? []
        for item in items { try? base.setSystemFields(nil, for: item) }
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecordMapping.zoneID))])
        enqueue(items.map { .save($0) })
    }

    func enqueue(_ changes: [SyncChange]) {
        guard let engine, !changes.isEmpty else { return }
        var saves: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in changes {
            switch change {
            case .save(let item): saves.append(.saveRecord(SyncRecordMapping.recordID(for: item)))
            case .delete(let item): saves.append(.deleteRecord(SyncRecordMapping.recordID(for: item)))
            }
        }
        engine.state.add(pendingRecordZoneChanges: saves)
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                status = .idle(lastSync: lastSync)
                enqueue(((try? base.allSyncItems()) ?? []).map { .save($0) })
            case .signOut, .switchAccounts:
                // Keep everything on this device; sync waits for the account to come back.
                status = .noAccount
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == SyncRecordMapping.zoneID {
                switch deletion.reason {
                case .encryptedDataReset:
                    // iCloud Keychain was reset, so CloudKit's encrypted fields are gone. This
                    // device still has the vault, so upload it again.
                    reuploadEverything(syncEngine)
                case .deleted, .purged:
                    // Deleted on purpose, from another device or from iCloud settings.
                    try? base.deleteAll()
                    onVaultDeletedRemotely?()
                @unknown default:
                    reuploadEverything(syncEngine)
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            var changed = false
            for modification in changes.modifications {
                changed = apply(modification.record) || changed
            }
            for deletion in changes.deletions {
                let isAttachment = deletion.recordType == SyncRecordMapping.RecordType.attachment
                switch SyncRecordMapping.item(for: deletion.recordID, isAttachment: isAttachment) {
                case .record(let id): try? base.deleteRecords(ids: [id])
                case .attachment(let id): try? base.deleteAttachments(ids: [id])
                case .meta, nil: continue
                }
                changed = true
            }
            if changed { onRemoteChanges?() }

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                if let item = item(for: record) {
                    try? base.setSystemFields(SyncRecordMapping.encodeSystemFields(record), for: item)
                }
            }
            for failure in sent.failedRecordSaves {
                handleFailedSave(failure.record, error: failure.error, engine: syncEngine)
            }

        case .willFetchChanges, .willSendChanges:
            status = .syncing
        case .didFetchChanges:
            hasCompletedFirstFetch = true
            lastSync = .now
            status = .idle(lastSync: lastSync)
        case .didSendChanges:
            lastSync = .now
            status = .idle(lastSync: lastSync)
        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        var records: [CKRecord] = []
        var deletions: [CKRecord.ID] = []
        var skipped: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending.prefix(200) {
            switch change {
            case .saveRecord(let id):
                if let record = outgoingRecord(id) {
                    records.append(record)
                } else {
                    skipped.append(change)
                }
            case .deleteRecord(let id):
                deletions.append(id)
            @unknown default:
                skipped.append(change)
            }
        }
        // Anything no longer in the store has nothing to send.
        if !skipped.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: skipped) }
        guard !records.isEmpty || !deletions.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, recordIDsToDelete: deletions)
    }

    // MARK: - Records

    private func outgoingRecord(_ id: CKRecord.ID) -> CKRecord? {
        do {
            if id.recordName == "meta" {
                guard let meta = try base.loadMeta() else { return nil }
                return try SyncRecordMapping.record(for: meta, systemFields: base.systemFields(for: .meta))
            }
            guard let uuid = UUID(uuidString: id.recordName) else { return nil }
            if let sealed = try base.loadRecord(id: uuid) {
                return SyncRecordMapping.record(for: sealed, systemFields: try base.systemFields(for: .record(uuid)))
            }
            if try base.hasAttachment(id: uuid), let url = try base.attachmentFileURL(id: uuid) {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                return SyncRecordMapping.attachmentRecord(
                    id: uuid, fileURL: url, size: size, systemFields: try base.systemFields(for: .attachment(uuid)))
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
        return nil
    }

    private func item(for record: CKRecord) -> SyncItem? {
        SyncRecordMapping.item(
            for: record.recordID, isAttachment: record.recordType == SyncRecordMapping.RecordType.attachment)
    }

    /// Writes a fetched record to the local store (not as a local change). Returns whether
    /// anything changed.
    @discardableResult
    private func apply(_ record: CKRecord) -> Bool {
        guard let incoming = SyncRecordMapping.incoming(record), let item = item(for: record) else { return false }
        do {
            switch incoming {
            case .meta(let meta):
                // Password-hashing limits this build won't run would lock every device out.
                guard meta.kdf.isWithinLimits else { return false }
                try base.saveMeta(meta)
            case .record(let sealed):
                if let accepts = acceptsIncomingRecord, !accepts(sealed) {
                    try base.setSystemFields(SyncRecordMapping.encodeSystemFields(record), for: item)
                    engine?.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
                    return false
                }
                try base.saveRecords([sealed])
            case .attachment(let id, let ciphertext): try base.saveAttachment(id: id, ciphertext: ciphertext)
            }
            try base.setSystemFields(SyncRecordMapping.encodeSystemFields(record), for: item)
            return true
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    private func handleFailedSave(_ record: CKRecord, error: CKError, engine: CKSyncEngine) {
        guard let item = item(for: record) else { return }
        switch error.code {
        case .serverRecordChanged:
            guard let server = error.serverRecord else { return }
            let local: SealedRecord? = if case .record(let id) = item { try? base.loadRecord(id: id) } else { nil }
            let localModified = local?.modified ?? (try? base.loadMeta())?.modified ?? .distantPast
            let serverModified = server[SyncRecordMapping.Key.modified] as? Date
            switch SyncRecordMapping.resolve(localModified: localModified, serverModified: serverModified) {
            case .takeServer:
                if let local, local.kind == .entry,
                    let incoming = SyncRecordMapping.incoming(server), case .record(let theirs) = incoming,
                    theirs.ciphertext != local.ciphertext
                {
                    onConflict?(local)
                }
                apply(server)
                onRemoteChanges?()
            case .keepLocal:
                try? base.setSystemFields(SyncRecordMapping.encodeSystemFields(server), for: item)
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }

        case .zoneNotFound:
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncRecordMapping.zoneID))])
            try? base.setSystemFields(nil, for: item)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .unknownItem:
            try? base.setSystemFields(nil, for: item)
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])

        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            // The engine retries these itself.
            break

        default:
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - Engine state

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        #if os(iOS)
            try? data.write(to: stateURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        #else
            try? data.write(to: stateURL, options: .atomic)
        #endif
    }
}
