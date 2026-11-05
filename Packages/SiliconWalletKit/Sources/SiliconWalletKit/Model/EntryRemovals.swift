import Foundation

/// What saving an edited entry deletes for good: attachments it no longer has, and extra fields
/// that had a value and are gone. An empty field is no loss, a cleared value is an edit, and an
/// extra field that moved into the group's field of the same name (`moved(from:to:)`) is kept.
public struct EntryRemovals: Equatable, Sendable {
    /// In the order the entry had them.
    public let attachments: [AttachmentRef]
    /// In the order the entry had them.
    public let extraFields: [CustomField]

    public var isEmpty: Bool { attachments.isEmpty && extraFields.isEmpty }
}

extension VaultEntry {
    /// What saving this entry over `original` deletes for good, so the editor can ask first.
    /// `group` is this entry's group: an extra field that's gone but whose label matches one of
    /// its fields with a value here moved into that field when the entry changed group.
    public func removals(since original: VaultEntry, in group: VaultGroup? = nil) -> EntryRemovals {
        let attachmentIDs = Set(attachments.map(\.id))
        let fieldIDs = Set(extraFields.map(\.id))
        let filledLabels = (group?.fields ?? []).filter { !Self.isBlank(values[$0.id] ?? "") }.map(\.label)
        return EntryRemovals(
            attachments: original.attachments.filter { !attachmentIDs.contains($0.id) },
            extraFields: original.extraFields.filter { field in
                !fieldIDs.contains(field.id) && !Self.isBlank(field.value)
                    && !filledLabels.contains { Self.sameLabel($0, field.label) }
            })
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
