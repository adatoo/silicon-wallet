import CryptoKit
import Foundation

/// A group of entries sharing one field template, such as "Web Logins" or "Credit Cards"
/// (DESIGN.md §4). Named `VaultGroup` so it doesn't clash with SwiftUI's `Group`.
public struct VaultGroup: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// An SF Symbol name.
    public var icon: String
    public var fields: [FieldTemplate]
    public var order: Int
    public var modified: Date

    public init(
        id: UUID = UUID(), name: String, icon: String = "folder", fields: [FieldTemplate] = [], order: Int = 0,
        modified: Date = .now
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.fields = fields
        self.order = order
        self.modified = modified
    }
}

/// One stored secret: its values keyed by the group's field IDs, plus any extra fields, notes
/// and attachments. Named `VaultEntry` to keep clear of SwiftUI's names.
public struct VaultEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var groupID: UUID
    public var title: String
    /// `FieldTemplate.id` → value. A template field with no value is simply absent.
    public var values: [UUID: String]
    public var extraFields: [CustomField]
    public var notes: String
    public var isFavorite: Bool
    public var attachments: [AttachmentRef]
    public var created: Date
    public var modified: Date

    public init(
        id: UUID = UUID(), groupID: UUID, title: String, values: [UUID: String] = [:],
        extraFields: [CustomField] = [], notes: String = "", isFavorite: Bool = false,
        attachments: [AttachmentRef] = [], created: Date = .now, modified: Date = .now
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.values = values
        self.extraFields = extraFields
        self.notes = notes
        self.isFavorite = isFavorite
        self.attachments = attachments
        self.created = created
        self.modified = modified
    }
}

/// An attachment as its entry knows it. The file itself is sealed separately under `fileKey`,
/// which exists only here, inside the entry's own encrypted payload (DESIGN.md §5).
public struct AttachmentRef: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var filename: String
    /// The uniform type identifier, such as `public.png`.
    public var uti: String
    public var size: Int64
    /// The raw 256-bit file key.
    public var fileKey: Data
    /// SHA-256 of the plaintext file, checked after opening.
    public var sha256: Data

    public init(id: UUID = UUID(), filename: String, uti: String, size: Int64, fileKey: Data, sha256: Data) {
        self.id = id
        self.filename = filename
        self.uti = uti
        self.size = size
        self.fileKey = fileKey
        self.sha256 = sha256
    }

    var symmetricKey: SymmetricKey { SymmetricKey(data: fileKey) }
}

/// The only vault data stored in the clear (DESIGN.md §5, §6): what's needed to derive the KEK
/// and unwrap the vault key.
public struct VaultMeta: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var kdf: KDFParameters
    public var wrappedVaultKey: Data
    /// `VaultKey.makeCheck(for:)`, to verify a vault key held outside the vault.
    public var keyCheck: Data
    public var created: Date
    public var modified: Date

    public init(
        formatVersion: Int, kdf: KDFParameters, wrappedVaultKey: Data, keyCheck: Data, created: Date, modified: Date
    ) {
        self.formatVersion = formatVersion
        self.kdf = kdf
        self.wrappedVaultKey = wrappedVaultKey
        self.keyCheck = keyCheck
        self.created = created
        self.modified = modified
    }
}
