import Foundation
import SwiftData

/// Identifies one synced CloudKit record: the vault metadata, a group or entry, or an
/// attachment's sealed file.
public enum SyncItem: Hashable, Sendable {
    case meta
    case record(UUID)
    case attachment(UUID)

    /// The CloudKit record name: `meta`, or the item's UUID.
    public var recordName: String {
        switch self {
        case .meta: "meta"
        case .record(let id), .attachment(let id): id.uuidString
        }
    }
}

/// What sync needs from the store beyond `VaultStore`: CloudKit system fields per item, a file
/// for each attachment's `CKAsset`, and writes that don't count as local changes.
@MainActor
public protocol SyncBackingStore: VaultStore {
    func systemFields(for item: SyncItem) throws -> Data?
    func setSystemFields(_ data: Data?, for item: SyncItem) throws
    /// Every item held locally, for a full re-upload.
    func allSyncItems() throws -> [SyncItem]
    /// Whether `id` is a sealed attachment file rather than a group or entry record.
    func hasAttachment(id: UUID) throws -> Bool
    /// A file holding the attachment's sealed bytes, for a `CKAsset`.
    func attachmentFileURL(id: UUID) throws -> URL?
    func loadRecord(id: UUID) throws -> SealedRecord?
}

extension InMemoryVaultStore: SyncBackingStore {
    public func systemFields(for item: SyncItem) throws -> Data? { systemFieldsByItem[item] }

    public func setSystemFields(_ data: Data?, for item: SyncItem) throws { systemFieldsByItem[item] = data }

    public func allSyncItems() throws -> [SyncItem] {
        (meta == nil ? [] : [.meta]) + records.keys.map(SyncItem.record) + attachments.keys.map(SyncItem.attachment)
    }

    public func hasAttachment(id: UUID) throws -> Bool { attachments[id] != nil }

    public func attachmentFileURL(id: UUID) throws -> URL? {
        guard let data = attachments[id] else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id.uuidString).bin")
        try data.write(to: url)
        return url
    }

    public func loadRecord(id: UUID) throws -> SealedRecord? { records[id] }
}

extension SwiftDataVaultStore: SyncBackingStore {
    public func systemFields(for item: SyncItem) throws -> Data? {
        switch item {
        case .meta: try metaModel()?.systemFields
        case .record(let id): try recordModel(id: id)?.systemFields
        case .attachment(let id): try attachmentModel(id: id)?.systemFields
        }
    }

    public func setSystemFields(_ data: Data?, for item: SyncItem) throws {
        switch item {
        case .meta: try metaModel()?.systemFields = data
        case .record(let id): try recordModel(id: id)?.systemFields = data
        case .attachment(let id): try attachmentModel(id: id)?.systemFields = data
        }
        try context.save()
    }

    public func allSyncItems() throws -> [SyncItem] {
        var items: [SyncItem] = try metaModel() == nil ? [] : [.meta]
        items += try loadRecords().map { .record($0.id) }
        items += try context.fetch(FetchDescriptor<AttachmentRecord>()).filter(\.isLocal).map { .attachment($0.id) }
        return items
    }

    public func hasAttachment(id: UUID) throws -> Bool { try attachmentModel(id: id)?.isLocal == true }

    public func attachmentFileURL(id: UUID) throws -> URL? {
        let url = attachmentURL(id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func loadRecord(id: UUID) throws -> SealedRecord? { try recordModel(id: id)?.sealedRecord }
}
