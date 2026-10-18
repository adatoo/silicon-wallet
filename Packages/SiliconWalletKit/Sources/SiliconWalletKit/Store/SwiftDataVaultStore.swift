import Foundation
import SwiftData

/// The vault on this device: a local-only SwiftData store of ciphertext envelopes, with sealed
/// attachment files beside it (DESIGN.md §6). It never sees plaintext.
@MainActor
public final class SwiftDataVaultStore: VaultStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    /// The folder of sealed attachment files, `<uuid>.bin`.
    public let attachmentsDirectory: URL

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    static let schema = Schema([VaultMetaRecord.self, SealedRecordModel.self, AttachmentRecord.self])

    /// Opens (or creates) the store in `directory`, normally the app's Application Support.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(
            schema: Self.schema, url: directory.appendingPathComponent("Vault.store"), cloudKitDatabase: .none)
        container = try ModelContainer(for: Self.schema, configurations: [configuration])
        attachmentsDirectory = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    /// A store held in memory, with attachments in a temporary folder: for tests and previews.
    public static func inMemory() throws -> SwiftDataVaultStore {
        try SwiftDataVaultStore(
            inMemoryWithAttachmentsIn: FileManager.default.temporaryDirectory
                .appendingPathComponent("SiliconWallet-\(UUID().uuidString)", isDirectory: true))
    }

    private init(inMemoryWithAttachmentsIn directory: URL) throws {
        let configuration = ModelConfiguration(schema: Self.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Self.schema, configurations: [configuration])
        attachmentsDirectory = directory
        try FileManager.default.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    /// `Application Support/com.datoos.silicon-wallet/Vault`. In the sandboxed app this is inside
    /// its own container; the bundle-ID folder keeps unsandboxed development builds apart too.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        .appendingPathComponent("com.datoos.silicon-wallet", isDirectory: true)
        .appendingPathComponent("Vault", isDirectory: true)
    }

    // MARK: - Meta

    func metaModel() throws -> VaultMetaRecord? {
        try context.fetch(FetchDescriptor<VaultMetaRecord>()).first
    }

    public func loadMeta() throws -> VaultMeta? {
        guard let record = try context.fetch(FetchDescriptor<VaultMetaRecord>()).first else { return nil }
        return try decoder.decode(VaultMeta.self, from: record.payload)
    }

    public func saveMeta(_ meta: VaultMeta) throws {
        let payload = try encoder.encode(meta)
        if let record = try context.fetch(FetchDescriptor<VaultMetaRecord>()).first {
            record.formatVersion = meta.formatVersion
            record.payload = payload
        } else {
            context.insert(VaultMetaRecord(formatVersion: meta.formatVersion, payload: payload))
        }
        try context.save()
    }

    // MARK: - Records

    public func loadRecords() throws -> [SealedRecord] {
        try context.fetch(FetchDescriptor<SealedRecordModel>()).compactMap(\.sealedRecord)
    }

    public func saveRecords(_ records: [SealedRecord]) throws {
        guard !records.isEmpty else { return }
        for record in records {
            if let existing = try recordModel(id: record.id) {
                existing.update(from: record)
            } else {
                context.insert(SealedRecordModel(record))
            }
        }
        try context.save()
    }

    public func deleteRecords(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let existing = try recordModel(id: id) { context.delete(existing) }
        }
        try context.save()
    }

    func recordModel(id: UUID) throws -> SealedRecordModel? {
        var descriptor = FetchDescriptor<SealedRecordModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Attachments

    func attachmentURL(_ id: UUID) -> URL {
        attachmentsDirectory.appendingPathComponent("\(id.uuidString).bin")
    }

    public func loadAttachment(id: UUID) throws -> Data? {
        let url = attachmentURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func saveAttachment(id: UUID, ciphertext: Data) throws {
        #if os(iOS)
            try ciphertext.write(to: attachmentURL(id), options: [.atomic, .completeFileProtection])
        #else
            try ciphertext.write(to: attachmentURL(id), options: .atomic)
        #endif
        if let record = try attachmentModel(id: id) {
            record.size = Int64(ciphertext.count)
            record.isLocal = true
        } else {
            context.insert(AttachmentRecord(id: id, size: Int64(ciphertext.count), isLocal: true))
        }
        try context.save()
    }

    public func deleteAttachments(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            try? FileManager.default.removeItem(at: attachmentURL(id))
            if let record = try attachmentModel(id: id) { context.delete(record) }
        }
        try context.save()
    }

    func attachmentModel(id: UUID) throws -> AttachmentRecord? {
        var descriptor = FetchDescriptor<AttachmentRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Everything

    public func deleteAll() throws {
        try context.delete(model: SealedRecordModel.self)
        try context.delete(model: AttachmentRecord.self)
        try context.delete(model: VaultMetaRecord.self)
        try context.save()
        let files =
            (try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: nil))
            ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}
