import Foundation
import SwiftData

/// The vault's unencrypted metadata (DESIGN.md §6). There is only ever one row.
@Model
final class VaultMetaRecord {
    var formatVersion: Int
    /// `VaultMeta`, JSON-encoded: the KDF parameters, the wrapped vault key and the key check.
    var payload: Data
    /// The CloudKit record's encoded system fields, once sync has saved it (step 6).
    var systemFields: Data?

    init(formatVersion: Int, payload: Data) {
        self.formatVersion = formatVersion
        self.payload = payload
    }
}

/// One sealed group or entry. Only the fields DESIGN.md §5 allows in the clear are columns;
/// everything else is inside `ciphertext`.
@Model
final class SealedRecordModel {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var modified: Date
    var schemaVersion: Int
    var ciphertext: Data
    var systemFields: Data?

    init(_ record: SealedRecord) {
        id = record.id
        kindRaw = record.kind.rawValue
        modified = record.modified
        schemaVersion = record.schemaVersion
        ciphertext = record.ciphertext
    }

    func update(from record: SealedRecord) {
        kindRaw = record.kind.rawValue
        modified = record.modified
        schemaVersion = record.schemaVersion
        ciphertext = record.ciphertext
    }

    var sealedRecord: SealedRecord? {
        guard let kind = RecordKind(rawValue: kindRaw) else { return nil }
        return SealedRecord(
            id: id, kind: kind, modified: modified, schemaVersion: schemaVersion, ciphertext: ciphertext)
    }
}

/// Bookkeeping for one attachment's sealed file. Which entry owns it is known only inside that
/// entry's ciphertext (DESIGN.md §6).
@Model
final class AttachmentRecord {
    @Attribute(.unique) var id: UUID
    var size: Int64
    /// Whether the sealed file is on this device; sync may fetch it later (step 7).
    var isLocal: Bool
    var systemFields: Data?

    init(id: UUID, size: Int64, isLocal: Bool) {
        self.id = id
        self.size = size
        self.isLocal = isLocal
    }
}
