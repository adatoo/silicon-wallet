import CryptoKit
import Foundation

/// Why an export file couldn't be imported.
public enum ExportFileError: Error, Equatable, Sendable {
    /// Neither a Silicon Wallet backup nor a Silicon Wallet JSON export.
    case notAnExport
    /// Written by a newer version of the format than this build reads.
    case unsupportedVersion
    /// The backup's password is wrong, or its sealed contents were changed. Not told apart.
    case wrongPasswordOrDamaged
    /// The file is cut short, malformed, or its parts don't fit together.
    case damaged
    /// Over `ExportFile.maximumFileSize`.
    case fileTooLarge
}

/// Reading and writing export files (ADR-0008): a password-protected Silicon Wallet backup, or
/// plaintext JSON. Both hold an `ExportDocument`; both are read entirely into memory.
///
/// A backup is
///
///     "SWBACKUP" ‖ format (UInt16) ‖ header length (UInt32) ‖ header (JSON: the KDF parameters)
///     ‖ sealed manifest length (UInt64) ‖ sealed manifest
///     ‖ for each attachment: its ID (16 bytes) ‖ sealed length (UInt64) ‖ sealed contents
///
/// with big-endian integers. The key is Argon2id of the export password under the header's
/// parameters (a fresh random salt per file). The manifest is the `ExportDocument` without
/// attachment data, sealed with no ID; each attachment is sealed with its own ID, so a chunk
/// can't pass as another. Only the KDF parameters are readable without the password.
public enum ExportFile {
    public static let backupExtension = "siliconwallet"
    /// The largest file read: 1 GiB. Everything in it is held in memory while importing.
    public static let maximumFileSize = 1 << 30
    static let magic = Data("SWBACKUP".utf8)
    static let backupFormat: UInt16 = 1
    static let maximumHeaderLength = 64 * 1024

    public enum Kind: Equatable, Sendable {
        case backup
        case json
    }

    /// What kind of export `data` looks like, from its first bytes; nil for neither.
    public static func kind(of data: Data) -> Kind? {
        if data.starts(with: magic) { return .backup }
        let firstByte = data.first { !Set(" \t\r\n".utf8).contains($0) }
        return firstByte == UInt8(ascii: "{") ? .json : nil
    }

    // MARK: - Writing

    /// The JSON export: the document with each attachment's contents inline, base64-encoded.
    static func json(_ document: ExportDocument) throws -> Data {
        try ExportDocument.encoder(pretty: true).encode(document)
    }

    /// Writes a backup: the header and sealed manifest first, then each attachment as it's added,
    /// so only one attachment's plaintext is in memory at a time.
    struct BackupWriter {
        private let key: SymmetricKey
        private(set) var data: Data

        /// `key` was derived from the export password with `kdf`.
        init(document: ExportDocument, key: SymmetricKey, kdf: KDFParameters) throws {
            self.key = key
            let header = try JSONEncoder().encode(BackupHeader(kdf: kdf))
            let manifest = try ExportDocument.encoder(pretty: false).encode(document)
            let sealedManifest = try Envelope.seal(manifest, key: key, purpose: .exportManifest, id: nil)
            data = ExportFile.magic
            data.appendBigEndian(ExportFile.backupFormat)
            data.appendBigEndian(UInt32(header.count))
            data.append(header)
            data.appendBigEndian(UInt64(sealedManifest.count))
            data.append(sealedManifest)
        }

        mutating func append(attachmentID id: UUID, contents: Data) throws {
            let sealed = try Envelope.seal(contents, key: key, purpose: .exportAttachment, id: id)
            withUnsafeBytes(of: id.uuid) { data.append(contentsOf: $0) }
            data.appendBigEndian(UInt64(sealed.count))
            data.append(sealed)
        }
    }

    // MARK: - Reading

    /// Reads a JSON export.
    public static func plan(
        json data: Data, maximumAttachmentSize: Int = VaultSession.maximumAttachmentSize
    ) throws -> VaultImportPlan {
        guard data.count <= maximumFileSize else { throw ExportFileError.fileTooLarge }
        let document = try decodeDocument(data)
        return try plan(document, maximumAttachmentSize: maximumAttachmentSize) { attachment in
            attachment.data
        }
    }

    /// Reads a backup with its export password. Runs Argon2id, so call it off the main actor.
    public static func plan(
        backup data: Data, password: String, maximumAttachmentSize: Int = VaultSession.maximumAttachmentSize
    ) throws -> VaultImportPlan {
        guard data.count <= maximumFileSize else { throw ExportFileError.fileTooLarge }
        var reader = ByteReader(data)
        guard try reader.read(magic.count) == magic else { throw ExportFileError.notAnExport }
        guard try reader.readUInt16() == backupFormat else { throw ExportFileError.unsupportedVersion }
        let headerLength = Int(try reader.readUInt32())
        guard headerLength <= maximumHeaderLength,
            let header = try? JSONDecoder().decode(BackupHeader.self, from: try reader.read(headerLength))
        else { throw ExportFileError.damaged }
        guard header.kdf.isWithinLimits else { throw ExportFileError.damaged }
        let sealedManifest = try reader.read(try reader.readLength())

        var sealedAttachments: [UUID: Data] = [:]
        while !reader.isAtEnd {
            let id = try reader.readUUID()
            let sealed = try reader.read(try reader.readLength())
            guard sealedAttachments.updateValue(sealed, forKey: id) == nil else { throw ExportFileError.damaged }
        }

        let key: SymmetricKey
        do {
            key = try KeyDerivation.deriveKEK(password: password, parameters: header.kdf)
        } catch CryptoError.invalidParameters {
            throw ExportFileError.damaged
        }
        let manifest: Data
        do {
            manifest = try Envelope.open(sealedManifest, key: key, purpose: .exportManifest, id: nil)
        } catch {
            throw ExportFileError.wrongPasswordOrDamaged
        }
        let document = try decodeDocument(manifest)
        var used = 0
        let plan = try plan(document, maximumAttachmentSize: maximumAttachmentSize) { attachment in
            // In a backup every attachment the manifest lists must be there and open.
            guard let sealed = sealedAttachments[attachment.id] else { throw ExportFileError.damaged }
            used += 1
            do {
                return try Envelope.open(sealed, key: key, purpose: .exportAttachment, id: attachment.id)
            } catch {
                throw ExportFileError.damaged
            }
        }
        // A chunk the manifest doesn't list was added to the file.
        guard used == sealedAttachments.count else { throw ExportFileError.damaged }
        return plan
    }

    private static func decodeDocument(_ data: Data) throws -> ExportDocument {
        struct Probe: Decodable {
            let format: String?
            let version: Int?
        }
        guard let probe = try? ExportDocument.decoder.decode(Probe.self, from: data),
            probe.format == ExportDocument.formatName, let version = probe.version
        else { throw ExportFileError.notAnExport }
        guard version <= ExportDocument.currentVersion else { throw ExportFileError.unsupportedVersion }
        do {
            return try ExportDocument.decoder.decode(ExportDocument.self, from: data)
        } catch {
            throw ExportFileError.damaged
        }
    }

    /// Maps a document onto the model. Repeated IDs keep their first use; a value whose key isn't a
    /// field ID becomes an extra field. `contents` gives an attachment's bytes, or nil if the file
    /// has none, in which case it's left out and counted.
    static func plan(
        _ document: ExportDocument, maximumAttachmentSize: Int,
        contents: (ExportAttachment) throws -> Data?
    ) throws -> VaultImportPlan {
        var seenGroups = Set<UUID>()
        let groups = document.groups.filter { seenGroups.insert($0.id).inserted }.map { group in
            var seenFields = Set<UUID>()
            return VaultGroup(
                id: group.id, name: group.name.isEmpty ? "Imported" : group.name,
                icon: group.icon.isEmpty ? "folder" : group.icon,
                fields: group.fields.filter { seenFields.insert($0.id).inserted }.map {
                    FieldTemplate(
                        id: $0.id, label: $0.label, kind: FieldKind(rawValue: $0.kind) ?? .text,
                        isConcealed: $0.concealed, isMonospaced: $0.monospaced)
                },
                order: group.order, modified: group.modified)
        }

        var plan = VaultImportPlan(groups: groups, entries: [], attachments: [])
        var seenEntries = Set<UUID>()
        var seenAttachments = Set<UUID>()
        for source in document.entries where seenEntries.insert(source.id).inserted {
            var values: [UUID: String] = [:]
            var extraFields: [CustomField] = []
            for (key, value) in source.values.sorted(by: { $0.key < $1.key }) {
                if let id = UUID(uuidString: key) {
                    values[id] = value
                } else {
                    extraFields.append(CustomField(label: "Field", value: value))
                }
            }
            var seenFields = Set<UUID>()
            extraFields =
                source.extraFields.filter { seenFields.insert($0.id).inserted }.map {
                    CustomField(
                        id: $0.id, label: $0.label, kind: FieldKind(rawValue: $0.kind) ?? .text,
                        isConcealed: $0.concealed, isMonospaced: $0.monospaced, value: $0.value ?? "")
                } + extraFields
            plan.entries.append(
                VaultEntry(
                    id: source.id, groupID: source.groupID, title: source.title, values: values,
                    extraFields: extraFields, notes: source.notes, isFavorite: source.favourite,
                    created: source.created, modified: source.modified))

            for attachment in source.attachments where seenAttachments.insert(attachment.id).inserted {
                guard let data = try contents(attachment) else {
                    plan.leftOutAttachmentCount += 1
                    continue
                }
                if let sha256 = attachment.sha256, Data(SHA256.hash(data: data)) != sha256 {
                    throw ExportFileError.damaged
                }
                guard data.count <= maximumAttachmentSize else {
                    plan.leftOutAttachmentCount += 1
                    continue
                }
                plan.attachments.append(
                    VaultImportPlan.Attachment(
                        entryID: source.id, filename: attachment.filename, uti: attachment.type, contents: data))
            }
        }
        return plan
    }
}

private struct BackupHeader: Codable {
    var kdf: KDFParameters
}

/// Reads a backup's parts, refusing to read past the end.
private struct ByteReader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset == data.endIndex }

    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, data.endIndex - offset >= count else { throw ExportFileError.damaged }
        defer { offset += count }
        return data.subdata(in: offset..<offset + count)
    }

    mutating func readUInt16() throws -> UInt16 { UInt16(try readInteger(2)) }
    mutating func readUInt32() throws -> UInt32 { UInt32(try readInteger(4)) }

    /// A UInt64 length that must fit in what's left of the file.
    mutating func readLength() throws -> Int {
        let length = try readInteger(8)
        guard length <= UInt64(data.endIndex - offset) else { throw ExportFileError.damaged }
        return Int(length)
    }

    mutating func readUUID() throws -> UUID {
        let bytes = Array(try read(16))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9],
                bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    private mutating func readInteger(_ count: Int) throws -> UInt64 {
        try read(count).reduce(0) { $0 << 8 | UInt64($1) }
    }
}

extension Data {
    fileprivate mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
