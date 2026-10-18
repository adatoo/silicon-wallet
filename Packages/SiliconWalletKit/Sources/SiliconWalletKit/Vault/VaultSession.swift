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

    public private(set) var state: State
    /// Every group, by `order`.
    public private(set) var groups: [VaultGroup] = []
    /// Every entry, by title.
    public private(set) var entries: [VaultEntry] = []
    /// Records that failed to open when the vault was unlocked or reloaded. They are left
    /// untouched in the store; a non-zero count means tampering or a damaged store.
    public private(set) var unreadableRecordCount = 0

    @ObservationIgnored private let store: any VaultStore
    @ObservationIgnored private var vaultKey: SymmetricKey?
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    @ObservationIgnored private let decoder = JSONDecoder()

    public init(store: any VaultStore) throws {
        self.store = store
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
        unreadableRecordCount = 0
        state = .unlocked
        if starterGroups {
            let starters = StarterGroups.make(now: now)
            try store.saveRecords(starters.map(seal))
            groups = starters
        }
    }

    /// Unlocks with the master password. Argon2id runs off the main actor.
    public func unlock(password: String) async throws {
        let meta = try requireMeta()
        let kek = try await Self.deriveKEK(password: password, kdf: meta.kdf)
        let key: SymmetricKey
        do {
            key = try VaultKey.unwrap(meta.wrappedVaultKey, kek: kek)
        } catch CryptoError.authenticationFailed {
            throw VaultError.wrongPassword
        }
        try open(with: key)
    }

    /// Unlocks with a vault key already held, from the biometric Keychain item (DESIGN.md §5).
    public func unlock(vaultKey key: SymmetricKey) throws {
        let meta = try requireMeta()
        guard VaultKey.verify(key, check: meta.keyCheck) else { throw VaultError.wrongPassword }
        try open(with: key)
    }

    /// The unlocked vault key, for the biometric Keychain item only. Nil while locked.
    public func vaultKeyForBiometricUnlock() -> SymmetricKey? { vaultKey }

    /// Forgets the vault key and every decrypted group and entry.
    public func lock() {
        vaultKey = nil
        groups = []
        entries = []
        unreadableRecordCount = 0
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
    }

    /// Checks the master password without changing anything, for re-authentication prompts.
    public func verifyPassword(_ password: String) async throws -> Bool {
        let meta = try requireMeta()
        let kek = try await Self.deriveKEK(password: password, kdf: meta.kdf)
        return (try? VaultKey.unwrap(meta.wrappedVaultKey, kek: kek)) != nil
    }

    /// Re-reads every record from the store, after sync has written remote changes into it.
    public func reload() throws {
        if state == .noVault, try store.loadMeta() != nil { state = .locked }
        guard let key = vaultKey else { return }
        try open(with: key)
    }

    /// Deletes the vault, and everything in it, from this device.
    public func deleteVault() throws {
        try store.deleteAll()
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
        try store.saveRecords([seal(group)])
        groups.append(group)
        return group
    }

    public func updateGroup(_ group: VaultGroup) throws {
        try requireUnlocked()
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { throw VaultError.notFound }
        var group = group
        group.modified = .now
        try store.saveRecords([seal(group)])
        groups[index] = group
        sortGroups()
    }

    /// Deletes a group with all its entries and their attachments.
    public func deleteGroup(id: UUID) throws {
        try requireUnlocked()
        guard groups.contains(where: { $0.id == id }) else { throw VaultError.notFound }
        let doomed = entries.filter { $0.groupID == id }
        try store.deleteRecords(ids: [id] + doomed.map(\.id))
        try store.deleteAttachments(ids: doomed.flatMap { $0.attachments.map(\.id) })
        groups.removeAll { $0.id == id }
        entries.removeAll { $0.groupID == id }
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
        let removed = Set(entries[index].attachments.map(\.id)).subtracting(entry.attachments.map(\.id))
        try store.saveRecords([seal(entry)])
        try store.deleteAttachments(ids: Array(removed))
        entries[index] = entry
        sortEntries()
    }

    public func deleteEntry(id: UUID) throws {
        try requireUnlocked()
        guard let entry = entry(id: id) else { throw VaultError.notFound }
        try store.deleteRecords(ids: [id])
        try store.deleteAttachments(ids: entry.attachments.map(\.id))
        entries.removeAll { $0.id == id }
    }

    public func setFavorite(_ isFavorite: Bool, entryID: UUID) throws {
        guard var entry = entry(id: entryID) else { throw VaultError.notFound }
        entry.isFavorite = isFavorite
        try updateEntry(entry)
    }

    // MARK: - Search

    /// Entries matching every word of `query`, optionally within one group. Matches titles,
    /// notes, attachment names, and the labels and values of fields that aren't concealed,
    /// ignoring case and diacritics. Concealed values are never searched.
    public func search(_ query: String, inGroup groupID: UUID? = nil) -> [VaultEntry] {
        let scope = groupID.map { entries(inGroup: $0) } ?? entries
        let words = Self.fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return scope }

        let groupsByID = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
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
        return (newGroups.count, newEntries.count, sealedFiles.count)
    }

    // MARK: - Sealing

    private func open(with key: SymmetricKey) throws {
        let meta = try requireMeta()
        guard meta.formatVersion <= SiliconWalletKit.formatVersion else {
            throw VaultError.unsupportedFormat(meta.formatVersion)
        }

        var openedGroups: [VaultGroup] = []
        var openedEntries: [VaultEntry] = []
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
                    openedGroups.append(group)
                } else {
                    unreadable += 1
                }
            case .entry:
                if let entry = try? decoder.decode(VaultEntry.self, from: plaintext), entry.id == record.id {
                    openedEntries.append(entry)
                } else {
                    unreadable += 1
                }
            }
        }

        vaultKey = key
        groups = openedGroups
        entries = openedEntries
        unreadableRecordCount = unreadable
        state = .unlocked
        sortGroups()
        sortEntries()
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

    private nonisolated static func deriveKEK(password: String, kdf: KDFParameters) async throws -> SymmetricKey {
        try await Task.detached(priority: .userInitiated) {
            try KeyDerivation.deriveKEK(password: password, parameters: kdf)
        }.value
    }
}
