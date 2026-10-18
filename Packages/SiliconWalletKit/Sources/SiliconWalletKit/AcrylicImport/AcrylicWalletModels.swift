import Foundation

/// A group ("category") from an Acrylic Wallet file's `groups` table.
///
/// `defaultHeadersArchive` is the field template list (type, UUID, title, section per field),
/// stored as an `NSKeyedArchiver` plist. Decoding it into `FieldTemplate` (DESIGN.md §4) is
/// follow-up work; this reader exposes the raw bytes so nothing is lost.
public struct AcrylicGroup: Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let icon: String?
    public let order: Int64
    public let uuid: String
    public let defaultHeadersArchive: Data?
}

/// An entry ("item") from an Acrylic Wallet file's `entries` table.
///
/// `fieldValues` is keyed by the owning field's UUID (match against the group's
/// `defaultHeadersArchive` to recover field labels). `extraHeadersText` is the entry's own
/// extra field definitions, in Wallet's old-style property-list text; decoding it is
/// follow-up work.
public struct AcrylicEntry: Sendable, Equatable {
    public let id: Int64
    public let title: String
    public let parentGroupUUID: String?
    public let notes: String
    public let fieldValues: [String: String]
    public let extraHeadersText: String?
    public let isStarred: Bool
    public let uuid: String
}

/// An attachment from an Acrylic Wallet file's `files` table.
public struct AcrylicFile: Sendable, Equatable {
    public let id: Int64
    public let uuid: String
    public let name: String
    public let size: Int64
    public let type: String?
    public let data: Data
}
