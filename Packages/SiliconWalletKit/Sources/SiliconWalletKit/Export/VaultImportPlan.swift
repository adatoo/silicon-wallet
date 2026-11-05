import Foundation

/// Groups, entries and attachment contents ready for `VaultSession.importItems`, from an Acrylic
/// Wallet file or a Silicon Wallet export. It holds plaintext, so it lives only in memory and only
/// until the import finishes.
public struct VaultImportPlan: Sendable {
    public struct Attachment: Sendable {
        public let entryID: UUID
        public let filename: String
        public let uti: String
        public let contents: Data

        public init(entryID: UUID, filename: String, uti: String, contents: Data) {
            self.entryID = entryID
            self.filename = filename
            self.uti = uti
            self.contents = contents
        }
    }

    /// Every group the file defines, including ones the vault may already have.
    public var groups: [VaultGroup]
    /// With no attachments: those come from `attachments`, sealed under new keys.
    public var entries: [VaultEntry]
    public var attachments: [Attachment]
    /// Attachments left out: over `VaultSession.maximumAttachmentSize`, or listed without contents.
    public var leftOutAttachmentCount = 0

    public init(groups: [VaultGroup], entries: [VaultEntry], attachments: [Attachment]) {
        self.groups = groups
        self.entries = entries
        self.attachments = attachments
    }
}

/// What an import adds, or would add, to the vault.
public struct ImportSummary: Equatable, Sendable {
    /// New groups.
    public var groups = 0
    /// Groups brought back from Recently Deleted because an imported entry belongs in them.
    public var restoredGroups = 0
    public var entries = 0
    public var attachments = 0
    /// Groups and entries left alone because the vault already has them (in use or deleted).
    public var groupsAlreadyHere = 0
    public var entriesAlreadyHere = 0
    /// Entries whose group is neither in the file nor in the vault, so they can't be placed.
    public var entriesWithoutGroup = 0

    public init() {}
}

extension VaultEntry {
    /// This entry with its values fitted to `group`, the group it's going into: a value for a field
    /// the group doesn't have becomes an extra field, labelled from `definition` (the group as
    /// the file defined it) or "Field" if that doesn't say. Nothing is dropped.
    func fitted(to group: VaultGroup, definedBy definition: VaultGroup?) -> VaultEntry {
        let fieldIDs = Set(group.fields.map(\.id))
        let definedOrder = definition?.fields.map(\.id) ?? []
        let loose = values.keys.filter { !fieldIDs.contains($0) }.sorted {
            (definedOrder.firstIndex(of: $0) ?? .max, $0.uuidString) < (
                definedOrder.firstIndex(of: $1) ?? .max, $1.uuidString
            )
        }
        var fitted = self
        fitted.values = values.filter { fieldIDs.contains($0.key) }
        for id in loose {
            guard let value = values[id], !value.isEmpty else { continue }
            let field = definition?.fields.first { $0.id == id }
            fitted.extraFields.append(
                CustomField(
                    label: field?.label ?? "Field", kind: field?.kind ?? .text, isConcealed: field?.isConcealed,
                    isMonospaced: field?.isMonospaced, value: value))
        }
        return fitted
    }
}
