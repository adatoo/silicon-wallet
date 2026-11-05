import Foundation

/// What an export holds (ADR-0008): the vault's groups and entries in use (not Recently
/// Deleted), with their attachments. The plaintext JSON export is this document as it is; a
/// Silicon Wallet backup seals it, without the attachments' data, as its manifest.
///
/// It's deliberately separate from the model's own `Codable` form, so the file format doesn't
/// change when the model does, and it never holds an attachment's file key.
public struct ExportDocument: Codable, Equatable, Sendable {
    public static let formatName = "silicon-wallet-export"
    public static let currentVersion = 1

    public var format: String
    public var version: Int
    public var exported: Date
    public var groups: [ExportGroup]
    public var entries: [ExportEntry]

    public init(exported: Date, groups: [ExportGroup], entries: [ExportEntry]) {
        format = Self.formatName
        version = Self.currentVersion
        self.exported = exported
        self.groups = groups
        self.entries = entries
    }
}

public struct ExportGroup: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol name.
    public var icon: String
    public var order: Int
    public var modified: Date
    public var fields: [ExportField]
}

/// A field of a group's template (no value), or an entry's extra field (with its value).
public struct ExportField: Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    /// A `FieldKind` raw value; one this build doesn't know reads as text.
    public var kind: String
    public var concealed: Bool
    public var monospaced: Bool
    public var value: String?
}

public struct ExportEntry: Codable, Equatable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var title: String
    /// The group's field ID (as a UUID string) → value.
    public var values: [String: String]
    public var extraFields: [ExportField]
    public var notes: String
    public var favourite: Bool
    public var created: Date
    public var modified: Date
    public var attachments: [ExportAttachment]
    /// The IDs of the entries this one links to, in order. Absent from files made before links
    /// existed, and when there are none.
    public var related: [UUID]?
    /// True when the password is kept in Apple Passwords; absent otherwise, and from older files.
    public var inApplePasswords: Bool? = nil
}

public struct ExportAttachment: Codable, Equatable, Sendable {
    public var id: UUID
    public var filename: String
    /// A uniform type identifier, such as `public.png`.
    public var type: String
    public var size: Int64
    public var sha256: Data?
    /// The file's contents, in a JSON export only; a backup seals each one separately.
    public var data: Data?
}

// MARK: - From the vault

extension ExportDocument {
    /// The document for these groups and entries, with no attachment data.
    init(groups: [VaultGroup], entries: [VaultEntry], exported: Date) {
        self.init(
            exported: exported,
            groups: groups.map { group in
                ExportGroup(
                    id: group.id, name: group.name, icon: group.icon, order: group.order, modified: group.modified,
                    fields: group.fields.map {
                        ExportField(
                            id: $0.id, label: $0.label, kind: $0.kind.rawValue, concealed: $0.isConcealed,
                            monospaced: $0.isMonospaced)
                    })
            },
            entries: entries.map { entry in
                ExportEntry(
                    id: entry.id, groupID: entry.groupID, title: entry.title,
                    values: Dictionary(uniqueKeysWithValues: entry.values.map { ($0.key.uuidString, $0.value) }),
                    extraFields: entry.extraFields.map {
                        ExportField(
                            id: $0.id, label: $0.label, kind: $0.kind.rawValue, concealed: $0.isConcealed,
                            monospaced: $0.isMonospaced, value: $0.value)
                    },
                    notes: entry.notes, favourite: entry.isFavorite, created: entry.created, modified: entry.modified,
                    attachments: entry.attachments.map {
                        ExportAttachment(
                            id: $0.id, filename: $0.filename, type: $0.uti, size: $0.size, sha256: $0.sha256)
                    },
                    related: entry.relatedIDs.isEmpty ? nil : entry.relatedIDs,
                    inApplePasswords: entry.passwordInApplePasswords ? true : nil)
            })
    }

    static func encoder(pretty: Bool) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
