import CloudKit
import Foundation

/// Turns local items into CloudKit records and back (DESIGN.md §7). Payloads go in
/// `encryptedValues`, so CloudKit's own encryption sits on top of ours; only the fields
/// DESIGN.md §5 allows in the clear are plain fields.
public enum SyncRecordMapping {
    public static let zoneID = CKRecordZone.ID(zoneName: "Vault", ownerName: CKCurrentUserDefaultName)

    public enum RecordType {
        public static let meta = "VaultMeta"
        public static let group = "Group"
        public static let entry = "Entry"
        public static let attachment = "Attachment"
    }

    enum Key {
        static let payload = "payload"
        static let modified = "modified"
        static let schemaVersion = "schemaVersion"
        static let formatVersion = "formatVersion"
        static let file = "file"
        static let size = "size"
    }

    public static func recordID(for item: SyncItem) -> CKRecord.ID {
        CKRecord.ID(recordName: item.recordName, zoneID: zoneID)
    }

    /// The item a record ID names. Attachments and records share the UUID form, so `isAttachment`
    /// decides (from the record type, or from the local store).
    public static func item(for recordID: CKRecord.ID, isAttachment: Bool) -> SyncItem? {
        if recordID.recordName == "meta" { return .meta }
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        return isAttachment ? .attachment(id) : .record(id)
    }

    // MARK: - System fields

    /// A record carrying the saved system fields (change tag and so on), or a new one.
    static func baseRecord(type: String, item: SyncItem, systemFields: Data?) -> CKRecord {
        if let systemFields, let decoded = decodeSystemFields(systemFields), decoded.recordType == type {
            return decoded
        }
        return CKRecord(recordType: type, recordID: recordID(for: item))
    }

    public static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    public static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: - Outgoing

    public static func record(for meta: VaultMeta, systemFields: Data?) throws -> CKRecord {
        let record = baseRecord(type: RecordType.meta, item: .meta, systemFields: systemFields)
        record.encryptedValues[Key.payload] = try JSONEncoder().encode(meta)
        record[Key.formatVersion] = meta.formatVersion
        record[Key.modified] = meta.modified
        return record
    }

    public static func record(for sealed: SealedRecord, systemFields: Data?) -> CKRecord {
        let type = sealed.kind == .group ? RecordType.group : RecordType.entry
        let record = baseRecord(type: type, item: .record(sealed.id), systemFields: systemFields)
        record.encryptedValues[Key.payload] = sealed.ciphertext
        record[Key.modified] = sealed.modified
        record[Key.schemaVersion] = sealed.schemaVersion
        return record
    }

    public static func attachmentRecord(id: UUID, fileURL: URL, size: Int, systemFields: Data?) -> CKRecord {
        let record = baseRecord(type: RecordType.attachment, item: .attachment(id), systemFields: systemFields)
        record[Key.file] = CKAsset(fileURL: fileURL)
        record[Key.size] = size
        return record
    }

    // MARK: - Incoming

    public enum Incoming: Sendable {
        case meta(VaultMeta)
        case record(SealedRecord)
        case attachment(id: UUID, ciphertext: Data)
    }

    public static func incoming(_ record: CKRecord) -> Incoming? {
        switch record.recordType {
        case RecordType.meta:
            guard let payload = record.encryptedValues[Key.payload] as? Data,
                let meta = try? JSONDecoder().decode(VaultMeta.self, from: payload)
            else { return nil }
            return .meta(meta)
        case RecordType.group, RecordType.entry:
            guard let id = UUID(uuidString: record.recordID.recordName),
                let ciphertext = record.encryptedValues[Key.payload] as? Data,
                let modified = record[Key.modified] as? Date
            else { return nil }
            return .record(
                SealedRecord(
                    id: id, kind: record.recordType == RecordType.group ? .group : .entry, modified: modified,
                    schemaVersion: record[Key.schemaVersion] as? Int ?? 1, ciphertext: ciphertext))
        case RecordType.attachment:
            guard let id = UUID(uuidString: record.recordID.recordName),
                let url = (record[Key.file] as? CKAsset)?.fileURL,
                let ciphertext = try? Data(contentsOf: url)
            else { return nil }
            return .attachment(id: id, ciphertext: ciphertext)
        default:
            return nil
        }
    }

    // MARK: - Conflicts

    public enum Resolution: Equatable, Sendable {
        /// Keep the server's version; the local one may be preserved as a conflict copy.
        case takeServer
        /// Re-send the local version on top of the server's change tag.
        case keepLocal
    }

    /// The later `modified` wins (DESIGN.md §7); a tie keeps the server's, so every device
    /// settles on the same version.
    public static func resolve(localModified: Date, serverModified: Date?) -> Resolution {
        guard let serverModified else { return .keepLocal }
        return localModified > serverModified ? .keepLocal : .takeServer
    }
}
