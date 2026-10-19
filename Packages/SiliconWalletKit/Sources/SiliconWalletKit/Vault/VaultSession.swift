import CryptoKit
import Foundation
import Observation

/// Errors from `VaultSession`.
public enum VaultError: Error, Equatable, Sendable {
    /// There is no vault on this device yet.
    case noVault
    /// A vault already exists, so a new one can't be created over it.
    case vaultExists
    /// The vault is locked; unlock it first.
    case locked
    case wrongPassword
    /// The vault was written by a newer format than this build reads.
    case unsupportedFormat(Int)
    /// No group, entry or attachment has that ID.
    case notFound
    /// An entry was saved into a group that doesn't exist.
    case unknownGroup
    /// An attachment's sealed file is missing from this device.
    case attachmentUnavailable
    /// An attachment opened, but its contents don't match the hash its entry recorded.
    case attachmentCorrupt
    /// Attachments are limited to `VaultSession.maximumAttachmentSize` (DESIGN.md §7).
    case attachmentTooLarge
}

/// The single way into a vault (DESIGN.md §3). Plaintext groups and entries exist only here,
/// in memory, and only while the vault is unlocked; everything that reaches the store is
/// sealed first.
@MainActor
@Observable
public final class VaultSession {
    public enum State: Equatable, Sendable {
        case noVault
        case locked
        case unlocked
    }

    /// The record schema written by this build, stored in the clear with each record.
    public static let recordSchemaVersion = 1
    /// The largest attachment accepted: 100 MB (DESIGN.md §7).
    public static let maximumAttachmentSize = 100 * 1024 * 1024
    /// How long groups and entries stay in Recently Deleted before they're deleted for good.
    public static let trashRetention: TimeInterval = 30 * 24 * 60 * 60

    /// How long this device shows an item in Recently Deleted, at least, before deleting it for
    /// good, whatever its deletion date says (`TrashLedger`).
    public static let minimumNotice: TimeInterval = 7 * 24 * 60 * 60

    /// When an item moved to Recently Deleted at `deletedAt` will be deleted for good, going by
    /// its deletion date alone.
    public static func purgeDate(forDeletedAt deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(trashRetention)
    }

    /// When the item `id` in Recently Deleted will be deleted for good: `trashRetention` after it
    /// was deleted, but not before this device has shown it for `minimumNotice`. A deletion date
    /// later than when this device first saw the item counts from when it was seen.
    public func purgeDate(forTrashedItem id: UUID, deletedAt: Date) -> Date {
        let seen = trashLedger.firstSeen(id) ?? .now
        return max(Self.purgeDate(forDeletedAt: min(deletedAt, seen)), seen.addingTimeInterval(Self.minimumNotice))
    }

    public private(set) var state: State
    /// Every group in use, by `order`. Groups in Recently Deleted are in `deletedGroups`.
    public private(set) var groups: [VaultGroup] = []
    /// Every entry in use, by title. Entries in Recently Deleted are in `deletedEntries`.
    public private(set) var entries: [VaultEntry] = []
    /// Groups in Recently Deleted, most recently deleted first.
    public private(set) var deletedGroups: [VaultGroup] = []
    /// Entries in Recently Deleted, most recently deleted first.
    public private(set) var deletedEntries: [VaultEntry] = []
    /// Records that failed to open when the vault was unlocked or reloaded. They are left
    /// untouched in the store; a non-zero count means tampering or a damaged store.
    public private(set) var unreadableRecordCount = 0

    @ObservationIgnored private let store: any VaultStore
    /// The device's access log, if this session keeps one (DESIGN.md §5).
    @ObservationIgnored public let accessLog: AccessLog?
    @ObservationIgnored private let trashLedger: TrashLedger
    @ObservationIgnored private var vaultKey: SymmetricKey?
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    @ObservationIgnored private let decoder = JSONDecoder()

    public init(
        store: any VaultStore, accessLog: AccessLog? = nil, trashLedger: TrashLedger = TrashLedger(directory: nil)
    ) throws {
        self.store = store
        self.accessLog = accessLog
        self.trashLedger = trashLedger
        self.state = try store.loadMeta() == nil ? .noVault : .locked
    }

    public var isUnlocked: Bool { state == .unlocked }

    // MARK: - Creating, unlocking and locking

    /// Creates a new vault protected by `password` and leaves it unlocked.
    public func createVault(
        password: String, starterGroups: Bool = true, kdf: KDFParameters = .generate()
    ) async throws {
        guard try store.loadMeta() == nil else { throw VaultError.vaultExists }

        let kek = try await Self.deriveKEK(password: password, kdf: kdf)
        let key = VaultKey.generate()
        let now = Date.now
        let meta = VaultMeta(
            formatVersion: SiliconWalletKit.formatVersion, kdf: kdf,
            wrappedVaultKey: try VaultKey.wrap(key, kek: kek), keyCheck: try VaultKey.makeCheck(for: key),
            created: now, modified: now)
        try store.saveMeta(meta)

        vaultKey = key
        groups = []
        entries = []
        deletedGroups = []
        deletedEntries = []
        unreadableRecordCount = 0
        state = .unlocked
        if starterGroups {
            let starters = StarterGroups.make(now: now)
            try store.saveRecords(starters.map(seal))
            groups = starters
        }
        accessLog?.record(AccessEvent(kind: .vaultCreated), key: key)
    }

    /// Unlocks with the master password. Argon2id runs off the main actor.
    public func unlock(password: String) async throws {
        let meta = try requireMeta()
        let kek = try await Self.deriveKEK(password: password, kdf: meta.kdf)
        let key: SymmetricKey
        do {
            key = try VaultKey.unwrap(meta.wrappedVaultKey, kek: kek)
        } catch CryptoError.authenticationFailed {
            accessLog?.recordWhileLocked(.failedUnlock)
            throw VaultError.wrongPassword
        }
        try open(with: key, purging: true)
        accessLog?.record(AccessEvent(kind: .unlockedWithPassword), key: key)
    }

    /// Unlocks with a vault key already held, from the biometric Keychain item (DESIGN.md §5).
    public func unlock(vaultKey key: SymmetricKey) throws {
        let meta = try requireMeta()
        guard VaultKey.verify(key, check: meta.keyCheck) else {
            accessLog?.recordWhileLocked(.failedUnlock)
            throw VaultError.wrongPassword
        }
        try open(with: key, purging: true)
        accessLog?.record(AccessEvent(kind: .unlockedWithBiometrics), key: key)
    }

    /// The unlocked vault key, for the biometric Keychain item only. Nil while locked.
    public func vaultKeyForBiometricUnlock() -> SymmetricKey? { vaultKey }

    /// Forgets the vault key and every decrypted group and entry.
    public func lock() {
        vaultKey = nil
        groups = []
        entries = []
        deletedGroups = []
        deletedEntries = []
        unreadableRecordCount = 0
        trashLedger.forget()
        if state == .unlocked { state = .locked }
    }

    /// Re-wraps the vault key under a new master password, with a fresh salt. Nothing else
    /// changes, so no records are re-encrypted (DESIGN.md §5).
    public func changePassword(current: String, new: String, kdf: KDFParameters = .generate()) async throws {
        var meta = try requireMeta()
        let oldKEK = try await Self.deriveKEK(password: current, kdf: meta.kdf)
        let key: SymmetricKey
        do {
            key = try VaultKey.unwrap(meta.wrappedVaultKey, kek: oldKEK)
        } catch CryptoError.authenticationFailed {
            throw VaultError.wrongPassword
        }
        let newKEK = try await Self.deriveKEK(password: new, kdf: kdf)
        meta.kdf = kdf
        meta.wrappedVaultKey = try VaultKey.wrap(key, kek: newKEK)
        meta.modified = .now
        try store.saveMeta(meta)
        accessLog?.record(AccessEvent(kind: .passwordChanged), key: key)
    }

    /// Checks the master password without changing anything, for re-authentication prompts.
    public func verifyPassword(_ password: String) async throws -> Bool {
        let meta = try requireMeta()
        let kek = try await Self.deriveKEK(password: password, kdf: meta.kdf)
        return (try? VaultKey.unwrap(meta.wrappedVaultKey, kek: kek)) != nil
    }

    /// Re-reads every record from the store, after sync has written remote changes into it. It
    /// never deletes anything for good: only an unlock does that.
    public func reload() throws {
        if state == .noVault, try store.loadMeta() != nil { state = .locked }
        guard let key = vaultKey else { return }
        try open(with: key, purging: false)
    }

    /// Forgets the vault after sync removed it because it was deleted on another device.
    public func vaultWasDeletedElsewhere() {
        lock()
        accessLog?.clear()
        trashLedger.clear()
        state = .noVault
    }

    /// Deletes the vault, and everything in it, from this device.
    public func deleteVault() throws {
        try store.deleteAll()
        accessLog?.clear()
        trashLedger.clear()
        lock()
        state = .noVault
    }

    // MARK: - Groups

    public func group(id: UUID) -> VaultGroup? { groups.first { $0.id == id } }

    @discardableResult
    public func addGroup(_ group: VaultGroup) throws -> VaultGroup {
        try requireUnlocked()
        var group = group
        group.order = (groups.map(\.order).max() ?? -1) + 1
        group.modified = .now
        group.deleted = nil
        try store.saveRecords([seal(group)])
        groups.append(group)
        return group
    }

    public func updateGroup(_ group: VaultGroup) throws {
        try requireUnlocked()
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { throw VaultError.notFound }
        var group = group
        group.modified = .now
        group.deleted = nil
        try store.saveRecords([seal(group)])
        groups[index] = group
        sortGroups()
    }

    /// Moves a group and every entry in it to Recently Deleted, all with the same deletion date,
    /// so restoring the group brings back exactly the entries deleted with it.
    public func moveGroupToTrash(id: UUID) throws {
        try requireUnlocked()
        guard var group = group(id: id) else { throw VaultError.notFound }
        let now = Date.now
        group.deleted = now
        group.modified = now
        var trashed = entries(inGroup: id)
        for index in trashed.indices {
            trashed[index].deleted = now
            trashed[index].modified = now
        }
        try store.saveRecords([try seal(group)] + (try trashed.map(seal)))
        groups.removeAll { $0.id == id }
        entries.removeAll { $0.groupID == id }
        deletedGroups.append(group)
        deletedEntries += trashed
        sortTrash()
        noteTrash()
    }

    /// Puts the groups in the given order (for drag-to-reorder).
    public func reorderGroups(_ ids: [UUID]) throws {
        try requireUnlocked()
        var changed: [VaultGroup] = []
        for (order, id) in ids.enumerated() {
            guard let index = groups.firstIndex(where: { $0.id == id }) else { throw VaultError.notFound }
            if groups[index].order != order {
                groups[index].order = order
                groups[index].modified = .now
                changed.append(groups[index])
            }
        }
        try store.saveRecords(changed.map(seal))
        sortGroups()
    }

    // MARK: - Entries

    public func entry(id: UUID) -> VaultEntry? { entries.first { $0.id == id } }

    public func entries(inGroup groupID: UUID) -> [VaultEntry] { entries.filter { $0.groupID == groupID } }

    public var favorites: [VaultEntry] { entries.filter(\.isFavorite) }

    @discardableResult
    public func addEntry(_ entry: VaultEntry) throws -> VaultEntry {
        try requireUnlocked()
        guard group(id: entry.groupID) != nil else { throw VaultError.unknownGroup }
        var entry = entry
        entry.created = .now
        entry.modified = entry.created
        entry.deleted = nil
        try store.saveRecords([seal(entry)])
        entries.append(entry)
        sortEntries()
        return entry
    }

    public func updateEntry(_ entry: VaultEntry) throws {
        try requireUnlocked()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { throw VaultError.notFound }
        guard group(id: entry.groupID) != nil else { throw VaultError.unknownGroup }
        var entry = entry
        entry.modified = .now
        entry.deleted = nil
        let removed = Set(entries[index].attachments.map(\.id)).subtracting(entry.attachments.map(\.id))
        try store.saveRecords([seal(entry)])
        try store.deleteAttachments(ids: Array(removed))
        entries[index] = entry
        sortEntries()
    }

    /// Moves an entry to Recently Deleted. Its attachments stay until it's deleted for good.
    public func moveEntryToTrash(id: UUID) throws {
        try requireUnlocked()
        guard var entry = entry(id: id) else { throw VaultError.notFound }
        let now = Date.now
        entry.deleted = now
        entry.modified = now
        try store.saveRecords([seal(entry)])
        entries.removeAll { $0.id == id }
        deletedEntries.append(entry)
        sortTrash()
        noteTrash()
    }

    public func setFavorite(_ isFavorite: Bool, entryID: UUID) throws {
        guard var entry = entry(id: entryID) else { throw VaultError.notFound }
        entry.isFavorite = isFavorite
        try updateEntry(entry)
    }

    // MARK: - Recently Deleted

    public func deletedGroup(id: UUID) -> VaultGroup? { deletedGroups.first { $0.id == id } }

    public func deletedEntry(id: UUID) -> VaultEntry? { deletedEntries.first { $0.id == id } }

    /// Takes an entry out of Recently Deleted. If its group is in Recently Deleted too, the group
    /// comes back with it (but not the group's other entries).
    public func restoreEntry(id: UUID) throws {
        try requireUnlocked()
        guard var entry = deletedEntry(id: id) else { throw VaultError.notFound }
        let now = Date.now
        var restoredGroup: VaultGroup?
        if group(id: entry.groupID) == nil {
            guard var group = deletedGroup(id: entry.groupID) else { throw VaultError.unknownGroup }
            group.deleted = nil
            group.modified = now
            restoredGroup = group
        }
        entry.deleted = nil
        entry.modified = now
        try store.saveRecords((try restoredGroup.map { [try seal($0)] } ?? []) + [try seal(entry)])
        if let restoredGroup {
            deletedGroups.removeAll { $0.id == restoredGroup.id }
            groups.append(restoredGroup)
            sortGroups()
        }
        deletedEntries.removeAll { $0.id == id }
        entries.append(entry)
        sortEntries()
    }

    /// Takes a group out of Recently Deleted with the entries deleted along with it. Entries
    /// deleted on their own before the group stay in Recently Deleted.
    public func restoreGroup(id: UUID) throws {
        try requireUnlocked()
        guard var group = deletedGroup(id: id), let deletedAt = group.deleted else { throw VaultError.notFound }
        let now = Date.now
        group.deleted = nil
        group.modified = now
        var restored = deletedEntries.filter { $0.groupID == id && $0.deleted == deletedAt }
        for index in restored.indices {
            restored[index].deleted = nil
            restored[index].modified = now
        }
        try store.saveRecords([try seal(group)] + (try restored.map(seal)))
        let restoredIDs = Set(restored.map(\.id))
        deletedGroups.removeAll { $0.id == id }
        deletedEntries.removeAll { restoredIDs.contains($0.id) }
        groups.append(group)
        entries += restored
        sortGroups()
        sortEntries()
    }

    /// Deletes an entry in Recently Deleted for good, with its attachments.
    public func deleteEntryPermanently(id: UUID) throws {
        try requireUnlocked()
        guard deletedEntry(id: id) != nil else { throw VaultError.notFound }
        try deletePermanently(groupIDs: [], entryIDs: [id])
    }

    /// Deletes a group in Recently Deleted for good, with the entries of it that are in Recently
    /// Deleted. An entry still in use (one added on another device as the group was deleted, say)
    /// is left alone.
    public func deleteGroupPermanently(id: UUID) throws {
        try requireUnlocked()
        guard deletedGroup(id: id) != nil else { throw VaultError.notFound }
        try deletePermanently(groupIDs: [id], entryIDs: deletedEntries.filter { $0.groupID == id }.map(\.id))
    }

    /// Deletes everything in Recently Deleted for good.
    public func emptyTrash() throws {
        try requireUnlocked()
        try deletePermanently(groupIDs: deletedGroups.map(\.id), entryIDs: deletedEntries.map(\.id))
    }

    /// Deletes for good whatever has reached its `purgeDate(forTrashedItem:deletedAt:)`, with any
    /// remaining entries of an expired group. Runs on unlock, never on a reload after sync; the
    /// deletion date is inside the ciphertext, so this can only happen while unlocked.
    @discardableResult
    public func purgeExpiredItems(now: Date = .now) throws -> Int {
        try requireUnlocked()
        let isExpired = { (id: UUID, deleted: Date?) in
            deleted.map { self.purgeDate(forTrashedItem: id, deletedAt: $0) <= now } ?? false
        }
        let groupIDs = Set(deletedGroups.filter { isExpired($0.id, $0.deleted) }.map(\.id))
        let entryIDs = deletedEntries.filter { isExpired($0.id, $0.deleted) || groupIDs.contains($0.groupID) }.map(\.id)
        guard !groupIDs.isEmpty || !entryIDs.isEmpty else { return 0 }
        try deletePermanently(groupIDs: Array(groupIDs), entryIDs: entryIDs)
        return groupIDs.count + entryIDs.count
    }

    private func deletePermanently(groupIDs: [UUID], entryIDs: [UUID]) throws {
        let doomedEntries = Set(entryIDs)
        let doomedGroups = Set(groupIDs)
        let attachments = deletedEntries.filter { doomedEntries.contains($0.id) }.flatMap { $0.attachments.map(\.id) }
        try store.deleteRecords(ids: groupIDs + entryIDs)
        try store.deleteAttachments(ids: attachments)
        deletedGroups.removeAll { doomedGroups.contains($0.id) }
        deletedEntries.removeAll { doomedEntries.contains($0.id) }
    }

    // MARK: - Search

    /// Entries matching every word of `query`, optionally within one group, or among the entries
    /// in Recently Deleted. Matches titles, notes, attachment names, and the labels and values of
    /// fields that aren't concealed, ignoring case and diacritics. Concealed values are never
    /// searched.
    public func search(_ query: String, inGroup groupID: UUID? = nil, inTrash: Bool = false) -> [VaultEntry] {
        let scope = inTrash ? deletedEntries : groupID.map { entries(inGroup: $0) } ?? entries
        let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return scope }

        let groupsByID = Dictionary((groups + deletedGroups).map { ($0.id, $0) }) { first, _ in first }
        return scope.filter { entry in
            let haystack = Self.fold(searchableText(entry, group: groupsByID[entry.groupID]))
            return words.allSatisfy { haystack.contains($0) }
        }
    }

    private func searchableText(_ entry: VaultEntry, group: VaultGroup?) -> String {
        var parts = [entry.title, entry.notes]
        for field in group?.fields ?? [] {
            guard let value = entry.values[field.id], !value.isEmpty else { continue }
            parts.append(field.label)
            if !field.isConcealed { parts.append(value) }
        }
        for field in entry.extraFields {
            parts.append(field.label)
            if !field.isConcealed { parts.append(field.value) }
        }
        parts += entry.attachments.map(\.filename)
        return parts.joined(separator: "\n")
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: - Attachments

    /// Seals `contents` under a new per-file key, stores it, and records it on the entry.
    @discardableResult
    public func addAttachment(to entryID: UUID, filename: String, uti: String, contents: Data) throws -> AttachmentRef {
        try requireUnlocked()
        guard var entry = entry(id: entryID) else { throw VaultError.notFound }
        guard contents.count <= Self.maximumAttachmentSize else { throw VaultError.attachmentTooLarge }
        let fileKey = AttachmentSealer.generateFileKey()
        let ref = AttachmentRef(
            filename: filename, uti: uti, size: Int64(contents.count),
            fileKey: fileKey.withUnsafeBytes { Data($0) }, sha256: Data(SHA256.hash(data: contents)))
        try store.saveAttachment(
            id: ref.id, ciphertext: AttachmentSealer.seal(contents, attachmentID: ref.id, fileKey: fileKey))
        entry.attachments.append(ref)
        try updateEntry(entry)
        return ref
    }

    /// The decrypted contents of an attachment, in memory.
    public func attachmentContents(_ ref: AttachmentRef) throws -> Data {
        try requireUnlocked()
        guard let sealed = try store.loadAttachment(id: ref.id) else { throw VaultError.attachmentUnavailable }
        let contents: Data
        do {
            contents = try AttachmentSealer.open(sealed, attachmentID: ref.id, fileKey: ref.symmetricKey)
        } catch {
            throw VaultError.attachmentCorrupt
        }
        guard Data(SHA256.hash(data: contents)) == ref.sha256 else { throw VaultError.attachmentCorrupt }
        return contents
    }

    /// Whether an attachment's sealed file is on this device (it may still be downloading).
    public func isAttachmentAvailable(_ ref: AttachmentRef) -> Bool {
        (try? store.loadAttachment(id: ref.id)) != nil
    }

    public func removeAttachment(id attachmentID: UUID, from entryID: UUID) throws {
        guard var entry = entry(id: entryID) else { throw VaultError.notFound }
        guard entry.attachments.contains(where: { $0.id == attachmentID }) else { throw VaultError.notFound }
        entry.attachments.removeAll { $0.id == attachmentID }
        try updateEntry(entry)
    }

    // MARK: - Access log

    /// Records something the app did, such as exporting an attachment. Ignored while locked.
    public func recordAccess(_ kind: AccessEvent.Kind, detail: String? = nil) {
        guard let vaultKey else { return }
        accessLog?.record(AccessEvent(kind: kind, detail: detail), key: vaultKey)
    }

    /// This device's access log, newest first. Empty while locked.
    public func accessEvents() -> [AccessEvent] {
        guard let vaultKey, let accessLog else { return [] }
        return accessLog.load(key: vaultKey)
    }

    // MARK: - Conflicts

    /// Keeps the losing side of a sync conflict as a new entry titled
    /// "<title> (conflict copy, <device>, <date>)" (DESIGN.md §7). Needs the vault unlocked;
    /// while locked the later version simply wins. The copy doesn't share the attachments,
    /// which stay with the winning version.
    @discardableResult
    public func keepConflictCopy(of record: SealedRecord, deviceName: String, at date: Date = .now) -> VaultEntry? {
        guard let vaultKey, record.kind == .entry,
            let plaintext = try? RecordSealer.open(record.ciphertext, recordID: record.id, key: vaultKey),
            var copy = try? decoder.decode(VaultEntry.self, from: plaintext),
            copy.deleted == nil, group(id: copy.groupID) != nil
        else { return nil }

        let stamp = date.formatted(date: .abbreviated, time: .shortened)
        copy.id = UUID()
        copy.title = "\(copy.title) (conflict copy, \(deviceName), \(stamp))"
        if !copy.attachments.isEmpty {
            let names = copy.attachments.map(\.filename).joined(separator: ", ")
            copy.notes += (copy.notes.isEmpty ? "" : "\n\n") + "Attachments kept on the other version: \(names)"
            copy.attachments = []
        }
        copy.modified = date
        guard (try? store.saveRecords([seal(copy)])) != nil else { return nil }
        entries.append(copy)
        sortEntries()
        return copy
    }

    // MARK: - Importing

    /// Adds imported groups and entries, keeping their dates, with each attachment sealed under
    /// its own new key. Everything is saved in one batch.
    @discardableResult
    public func importItems(_ plan: AcrylicImportPlan) throws -> (groups: Int, entries: Int, attachments: Int) {
        try requireUnlocked()
        let firstOrder = (groups.map(\.order).max() ?? -1) + 1
        var newGroups = plan.groups
        for index in newGroups.indices { newGroups[index].order = firstOrder + index }
        let groupIDs = Set(newGroups.map(\.id))

        var newEntries = plan.entries.filter { groupIDs.contains($0.groupID) }
        var indexByEntryID: [UUID: Int] = [:]
        for (index, entry) in newEntries.enumerated() { indexByEntryID[entry.id] = index }

        var sealedFiles: [(UUID, Data)] = []
        for attachment in plan.attachments {
            guard let index = indexByEntryID[attachment.entryID] else { continue }
            let fileKey = AttachmentSealer.generateFileKey()
            let ref = AttachmentRef(
                filename: attachment.filename, uti: attachment.uti, size: Int64(attachment.contents.count),
                fileKey: fileKey.withUnsafeBytes { Data($0) }, sha256: Data(SHA256.hash(data: attachment.contents)))
            sealedFiles.append(
                (ref.id, try AttachmentSealer.seal(attachment.contents, attachmentID: ref.id, fileKey: fileKey)))
            newEntries[index].attachments.append(ref)
        }

        for (id, ciphertext) in sealedFiles { try store.saveAttachment(id: id, ciphertext: ciphertext) }
        try store.saveRecords(try newGroups.map(seal) + newEntries.map(seal))
        groups += newGroups
        entries += newEntries
        sortGroups()
        sortEntries()
        if let vaultKey {
            accessLog?.record(
                AccessEvent(kind: .imported, detail: "\(newEntries.count) entries, \(newGroups.count) groups"),
                key: vaultKey)
        }
        return (newGroups.count, newEntries.count, sealedFiles.count)
    }

    // MARK: - Sealing

    private func open(with key: SymmetricKey, purging: Bool) throws {
        let meta = try requireMeta()
        guard meta.formatVersion <= SiliconWalletKit.formatVersion else {
            throw VaultError.unsupportedFormat(meta.formatVersion)
        }

        var openedGroups: [VaultGroup] = []
        var openedEntries: [VaultEntry] = []
        var openedDeletedGroups: [VaultGroup] = []
        var openedDeletedEntries: [VaultEntry] = []
        var unreadable = 0
        for record in try store.loadRecords() {
            guard record.schemaVersion <= Self.recordSchemaVersion,
                let plaintext = try? RecordSealer.open(record.ciphertext, recordID: record.id, key: key)
            else {
                unreadable += 1
                continue
            }
            switch record.kind {
            case .group:
                if let group = try? decoder.decode(VaultGroup.self, from: plaintext), group.id == record.id {
                    if group.deleted == nil {
                        openedGroups.append(group)
                    } else {
                        openedDeletedGroups.append(group)
                    }
                } else {
                    unreadable += 1
                }
            case .entry:
                if let entry = try? decoder.decode(VaultEntry.self, from: plaintext), entry.id == record.id {
                    if entry.deleted == nil {
                        openedEntries.append(entry)
                    } else {
                        openedDeletedEntries.append(entry)
                    }
                } else {
                    unreadable += 1
                }
            }
        }

        vaultKey = key
        groups = openedGroups
        entries = openedEntries
        deletedGroups = openedDeletedGroups
        deletedEntries = openedDeletedEntries
        unreadableRecordCount = unreadable
        state = .unlocked
        sortGroups()
        sortEntries()
        sortTrash()
        trashLedger.load(key: key)
        noteTrash()
        // A purge that fails now is tried again at the next unlock.
        if purging { _ = try? purgeExpiredItems() }
    }

    private func seal(_ group: VaultGroup) throws -> SealedRecord {
        try seal(encoder.encode(group), id: group.id, kind: .group, modified: group.modified)
    }

    private func seal(_ entry: VaultEntry) throws -> SealedRecord {
        try seal(encoder.encode(entry), id: entry.id, kind: .entry, modified: entry.modified)
    }

    private func seal(_ plaintext: Data, id: UUID, kind: RecordKind, modified: Date) throws -> SealedRecord {
        guard let vaultKey else { throw VaultError.locked }
        return SealedRecord(
            id: id, kind: kind, modified: modified, schemaVersion: Self.recordSchemaVersion,
            ciphertext: try RecordSealer.seal(plaintext, recordID: id, key: vaultKey))
    }

    private func requireMeta() throws -> VaultMeta {
        guard let meta = try store.loadMeta() else { throw VaultError.noVault }
        return meta
    }

    private func requireUnlocked() throws {
        guard vaultKey != nil, state == .unlocked else { throw VaultError.locked }
    }

    private func sortGroups() {
        groups.sort { ($0.order, $0.name) < ($1.order, $1.name) }
    }

    private func sortEntries() {
        entries.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Records in the ledger which items are in Recently Deleted now.
    private func noteTrash() {
        guard let vaultKey else { return }
        let ids = Set(deletedGroups.map(\.id) + deletedEntries.map(\.id))
        trashLedger.update(trashed: ids, now: .now, key: vaultKey)
    }

    private func sortTrash() {
        deletedGroups.sort { ($0.deleted ?? .distantPast) > ($1.deleted ?? .distantPast) }
        deletedEntries.sort { ($0.deleted ?? .distantPast) > ($1.deleted ?? .distantPast) }
    }

    private nonisolated static func deriveKEK(password: String, kdf: KDFParameters) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            try KeyDerivation.deriveKEK(password: password, parameters: kdf)
        }.value
    }
}
