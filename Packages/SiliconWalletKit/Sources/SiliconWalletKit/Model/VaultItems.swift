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
    /// When the group was moved to Recently Deleted; nil while it's in use.
    public var deleted: Date?

    public init(
        id: UUID = UUID(), name: String, icon: String = "folder", fields: [FieldTemplate] = [], order: Int = 0,
        modified: Date = .now, deleted: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.fields = fields
        self.order = order
        self.modified = modified
        self.deleted = deleted
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
    /// Entries this one links to, in the order shown (DESIGN.md §4). A link is stored on one side
    /// and shown on both (`VaultSession.relatedEntries(of:)`); it lives only in the sealed payload.
    public var relatedIDs: [UUID]
    /// The password is kept in Apple Passwords rather than here (DESIGN.md §3): the group's
    /// password fields are hidden and left empty, and the other values stay. Sealed like the rest.
    public var passwordInApplePasswords: Bool
    public var created: Date
    public var modified: Date
    /// When the entry was moved to Recently Deleted; nil while it's in use.
    public var deleted: Date?

    public init(
        id: UUID = UUID(), groupID: UUID, title: String, values: [UUID: String] = [:],
        extraFields: [CustomField] = [], notes: String = "", isFavorite: Bool = false,
        attachments: [AttachmentRef] = [], relatedIDs: [UUID] = [], passwordInApplePasswords: Bool = false,
        created: Date = .now, modified: Date = .now, deleted: Date? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.values = values
        self.extraFields = extraFields
        self.notes = notes
        self.isFavorite = isFavorite
        self.attachments = attachments
        self.relatedIDs = relatedIDs
        self.passwordInApplePasswords = passwordInApplePasswords
        self.created = created
        self.modified = modified
        self.deleted = deleted
    }

    /// Records written before `relatedIDs` existed have no links, and those written before
    /// `passwordInApplePasswords` keep their password here.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        groupID = try container.decode(UUID.self, forKey: .groupID)
        title = try container.decode(String.self, forKey: .title)
        values = try container.decode([UUID: String].self, forKey: .values)
        extraFields = try container.decode([CustomField].self, forKey: .extraFields)
        notes = try container.decode(String.self, forKey: .notes)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        attachments = try container.decode([AttachmentRef].self, forKey: .attachments)
        relatedIDs = try container.decodeIfPresent([UUID].self, forKey: .relatedIDs) ?? []
        passwordInApplePasswords =
            try container.decodeIfPresent(Bool.self, forKey: .passwordInApplePasswords) ?? false
        created = try container.decode(Date.self, forKey: .created)
        modified = try container.decode(Date.self, forKey: .modified)
        deleted = try container.decodeIfPresent(Date.self, forKey: .deleted)
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

extension VaultGroup {
    /// The group's password fields: the ones hidden and left empty when an entry keeps its
    /// password in Apple Passwords. Empty when the group has none, and the option isn't offered.
    public var passwordFieldIDs: [UUID] { fields.filter { $0.kind == .password }.map(\.id) }
}
