import Foundation

/// What saving an edited entry deletes for good: attachments it no longer has, and extra fields
/// that had a value and are gone. An empty field is no loss, and a cleared value is an edit.
public struct EntryRemovals: Equatable, Sendable {
    /// In the order the entry had them.
    public let attachments: [AttachmentRef]
    /// In the order the entry had them.
    public let extraFields: [CustomField]

    public var isEmpty: Bool { attachments.isEmpty && extraFields.isEmpty }
}

extension VaultEntry {
    /// What saving this entry over `original` deletes for good, so the editor can ask first.
    public func removals(since original: VaultEntry) -> EntryRemovals {
        let attachmentIDs = Set(attachments.map(\.id))
        let fieldIDs = Set(extraFields.map(\.id))
        return EntryRemovals(
            attachments: original.attachments.filter { !attachmentIDs.contains($0.id) },
            extraFields: original.extraFields.filter {
                !fieldIDs.contains($0.id) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
    }
}
