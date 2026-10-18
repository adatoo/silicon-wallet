import Foundation

extension VaultEntry {
    /// This entry moved from `old` to `new`, keeping every value. A value whose field label
    /// matches a field in the new group (ignoring case) moves into that field; any other value
    /// becomes an extra field on the entry, so nothing is lost.
    public func moved(from old: VaultGroup, to new: VaultGroup) -> VaultEntry {
        guard old.id != new.id else { return self }
        var moved = self
        moved.groupID = new.id
        moved.values = [:]

        var unclaimed = new.fields
        for field in old.fields {
            guard let value = values[field.id], !value.isEmpty else { continue }
            if let index = unclaimed.firstIndex(where: { Self.sameLabel($0.label, field.label) }) {
                moved.values[unclaimed[index].id] = value
                unclaimed.remove(at: index)
            } else {
                moved.extraFields.append(
                    CustomField(label: field.label, kind: field.kind, isConcealed: field.isConcealed, value: value))
            }
        }

        // Extra fields that now match an unfilled template field move into it.
        moved.extraFields = moved.extraFields.filter { extra in
            guard let index = unclaimed.firstIndex(where: { Self.sameLabel($0.label, extra.label) }) else {
                return true
            }
            moved.values[unclaimed[index].id] = extra.value
            unclaimed.remove(at: index)
            return false
        }
        return moved
    }

    private static func sameLabel(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespaces))
            == .orderedSame
    }
}
