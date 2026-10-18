import Foundation

/// The kinds of encrypted record a vault holds (DESIGN.md §6, §7).
public enum RecordKind: String, Codable, Sendable {
    case group
    case entry
}

/// One encrypted group or entry as the store and sync see it. Only these fields are in the
/// clear (DESIGN.md §5): the ID, the kind, the modified date, the schema version and, by
/// implication, the ciphertext's length.
public struct SealedRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: RecordKind
    public var modified: Date
    public var schemaVersion: Int
    public var ciphertext: Data

    public init(id: UUID, kind: RecordKind, modified: Date, schemaVersion: Int, ciphertext: Data) {
        self.id = id
        self.kind = kind
        self.modified = modified
        self.schemaVersion = schemaVersion
        self.ciphertext = ciphertext
    }
}

/// Where a vault's ciphertext lives. `VaultSession` is the only caller, and it never hands a
/// store anything but sealed bytes and the unencrypted metadata.
@MainActor
public protocol VaultStore: AnyObject {
    func loadMeta() throws -> VaultMeta?
    func saveMeta(_ meta: VaultMeta) throws

    func loadRecords() throws -> [SealedRecord]
    /// Inserts or replaces records by ID, in one save.
    func saveRecords(_ records: [SealedRecord]) throws
    func deleteRecords(ids: [UUID]) throws

    func loadAttachment(id: UUID) throws -> Data?
    func saveAttachment(id: UUID, ciphertext: Data) throws
    func deleteAttachments(ids: [UUID]) throws

    /// Removes the whole vault from this device.
    func deleteAll() throws
}

/// A store that keeps everything in memory: for tests and previews.
@MainActor
public final class InMemoryVaultStore: VaultStore {
    public private(set) var meta: VaultMeta?
    public private(set) var records: [UUID: SealedRecord] = [:]
    public private(set) var attachments: [UUID: Data] = [:]

    public init() {}

    public func loadMeta() throws -> VaultMeta? { meta }
    public func saveMeta(_ meta: VaultMeta) throws { self.meta = meta }

    public func loadRecords() throws -> [SealedRecord] { Array(records.values) }
    public func saveRecords(_ records: [SealedRecord]) throws {
        for record in records { self.records[record.id] = record }
    }
    public func deleteRecords(ids: [UUID]) throws {
        for id in ids { records[id] = nil }
    }

    public func loadAttachment(id: UUID) throws -> Data? { attachments[id] }
    public func saveAttachment(id: UUID, ciphertext: Data) throws { attachments[id] = ciphertext }
    public func deleteAttachments(ids: [UUID]) throws {
        for id in ids { attachments[id] = nil }
    }

    public func deleteAll() throws {
        meta = nil
        records = [:]
        attachments = [:]
    }
}
