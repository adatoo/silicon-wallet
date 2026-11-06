import Foundation

/// A bank account's sort code and account number, read from a debit card (DESIGN.md §3). They
/// belong to the bank account the card is related to, not the card, so they're written to that
/// entry, or to a new one, instead of the card's own fields.
public struct BankDetails: Equatable, Sendable {
    /// `12-34-56`.
    public var sortCode: String?
    /// Digits only.
    public var accountNumber: String?

    public init(sortCode: String? = nil, accountNumber: String? = nil) {
        self.sortCode = sortCode
        self.accountNumber = accountNumber
    }

    /// What a scan found, or nil if it found neither.
    public init?(card: ScannedCard) {
        guard card.sortCode != nil || card.accountNumber != nil else { return nil }
        self.init(sortCode: card.sortCode, accountNumber: card.accountNumber)
    }

    /// How these would go into an existing entry.
    public enum Fit: Equatable, Sendable {
        /// The entry already has them.
        case same
        /// Only empty values would be filled.
        case fills
        /// A value there now would be replaced.
        case differs
    }

    /// Whether a group is for bank accounts: it has a sort code or account number field.
    public static func isBankAccountGroup(_ group: VaultGroup) -> Bool {
        group.fields.contains { CardField(label: $0.label)?.isBankAccount == true }
    }

    public func fit(_ entry: VaultEntry, in group: VaultGroup) -> Fit {
        var fit = Fit.same
        for (kind, value) in values {
            let current = Self.current(kind, of: entry, in: group) ?? ""
            if current.isEmpty {
                fit = fit == .differs ? .differs : .fills
            } else if Self.digits(current) != Self.digits(value) {
                return .differs
            }
        }
        return fit
    }

    /// `entry` with these written in: into its fields with matching labels, the group's first,
    /// or as new extra fields where it has none.
    public func applied(to entry: VaultEntry, in group: VaultGroup) -> VaultEntry {
        var entry = entry
        for (kind, value) in values {
            if let field = group.fields.first(where: { CardField(label: $0.label) == kind }) {
                entry.values[field.id] = value
            } else if let index = entry.extraFields.firstIndex(where: { CardField(label: $0.label) == kind }) {
                entry.extraFields[index].value = value
            } else {
                entry.extraFields.append(
                    CustomField(
                        label: kind == .sortCode ? "Sort Code" : "Account Number", kind: .number,
                        isConcealed: kind == .accountNumber, value: value))
            }
        }
        return entry
    }

    /// A new entry in `group` holding these.
    public func newAccount(in group: VaultGroup, title: String) -> VaultEntry {
        applied(to: VaultEntry(groupID: group.id, title: title), in: group)
    }

    private var values: [(CardField, String)] {
        [(.sortCode, sortCode), (.accountNumber, accountNumber)].compactMap { kind, value in
            value.map { (kind, $0) }
        }
    }

    private static func current(_ kind: CardField, of entry: VaultEntry, in group: VaultGroup) -> String? {
        if let field = group.fields.first(where: { CardField(label: $0.label) == kind }),
            let value = entry.values[field.id], !value.isEmpty
        {
            return value
        }
        return entry.extraFields.first { CardField(label: $0.label) == kind && !$0.value.isEmpty }?.value
    }

    private static func digits(_ value: String) -> String { value.filter(\.isNumber) }
}
