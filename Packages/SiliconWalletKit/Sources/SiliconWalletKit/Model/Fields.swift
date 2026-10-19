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

    /// Whether a field's value is shown in a monospaced font when nothing says otherwise:
    /// passwords and concealed values are, as they were before the option existed.
    public func isMonospacedByDefault(isConcealed: Bool) -> Bool { isConcealed || self == .password }
}

/// One field in a group's template. Labels live on the group, so every entry in it shares
/// them (DESIGN.md §4).
public struct FieldTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: FieldKind
    public var isConcealed: Bool
    /// Whether the value (never the label) is shown in a monospaced font.
    public var isMonospaced: Bool

    public init(
        id: UUID = UUID(), label: String, kind: FieldKind = .text, isConcealed: Bool? = nil, isMonospaced: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.isConcealed = isConcealed ?? kind.isConcealedByDefault
        self.isMonospaced = isMonospaced ?? kind.isMonospacedByDefault(isConcealed: self.isConcealed)
    }

    /// Records written before `isMonospaced` existed get the default for their kind.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        kind = try container.decode(FieldKind.self, forKey: .kind)
        isConcealed = try container.decode(Bool.self, forKey: .isConcealed)
        isMonospaced =
            try container.decodeIfPresent(Bool.self, forKey: .isMonospaced)
            ?? kind.isMonospacedByDefault(isConcealed: isConcealed)
    }
}

/// A field added to one entry only, outside its group's template.
public struct CustomField: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: FieldKind
    public var isConcealed: Bool
    /// Whether the value (never the label) is shown in a monospaced font.
    public var isMonospaced: Bool
    public var value: String

    public init(
        id: UUID = UUID(), label: String, kind: FieldKind = .text, isConcealed: Bool? = nil,
        isMonospaced: Bool? = nil, value: String = ""
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.isConcealed = isConcealed ?? kind.isConcealedByDefault
        self.isMonospaced = isMonospaced ?? kind.isMonospacedByDefault(isConcealed: self.isConcealed)
        self.value = value
    }

    /// Records written before `isMonospaced` existed get the default for their kind.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        kind = try container.decode(FieldKind.self, forKey: .kind)
        isConcealed = try container.decode(Bool.self, forKey: .isConcealed)
        isMonospaced =
            try container.decodeIfPresent(Bool.self, forKey: .isMonospaced)
            ?? kind.isMonospacedByDefault(isConcealed: isConcealed)
        value = try container.decode(String.self, forKey: .value)
    }
}
