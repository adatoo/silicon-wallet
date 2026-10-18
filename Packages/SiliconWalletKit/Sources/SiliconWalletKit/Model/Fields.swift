import Foundation

/// What a field holds. It decides the keyboard, how the value is shown, and whether it can be
/// opened or dialled.
public enum FieldKind: String, Codable, CaseIterable, Sendable {
    case text
    case password
    case number
    case date
    case url
    case email
    case phone
    case multiline

    /// Passwords are concealed unless the template says otherwise.
    public var isConcealedByDefault: Bool { self == .password }
}

/// One field in a group's template. Labels live on the group, so every entry in it shares
/// them (DESIGN.md §4).
public struct FieldTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: FieldKind
    public var isConcealed: Bool

    public init(id: UUID = UUID(), label: String, kind: FieldKind = .text, isConcealed: Bool? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.isConcealed = isConcealed ?? kind.isConcealedByDefault
    }
}

/// A field added to one entry only, outside its group's template.
public struct CustomField: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: FieldKind
    public var isConcealed: Bool
    public var value: String

    public init(
        id: UUID = UUID(), label: String, kind: FieldKind = .text, isConcealed: Bool? = nil, value: String = ""
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.isConcealed = isConcealed ?? kind.isConcealedByDefault
        self.value = value
    }
}
