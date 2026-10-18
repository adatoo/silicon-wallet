import Foundation

/// The groups a new vault starts with, so the first entry is one tap away. Users can rename,
/// edit or delete them like any other group.
public enum StarterGroups {
    public static func make(now: Date = .now) -> [VaultGroup] {
        [
            VaultGroup(
                name: "Logins", icon: "person.badge.key",
                fields: [
                    FieldTemplate(label: "Username"),
                    FieldTemplate(label: "Password", kind: .password),
                    FieldTemplate(label: "Website", kind: .url),
                ], order: 0, modified: now),
            VaultGroup(
                name: "Credit Cards", icon: "creditcard",
                fields: [
                    FieldTemplate(label: "Cardholder"),
                    FieldTemplate(label: "Card Number", kind: .number, isConcealed: true),
                    FieldTemplate(label: "Expiry"),
                    FieldTemplate(label: "Security Code", kind: .number, isConcealed: true),
                    FieldTemplate(label: "PIN", kind: .number, isConcealed: true),
                ], order: 1, modified: now),
            VaultGroup(
                name: "Bank Accounts", icon: "building.columns",
                fields: [
                    FieldTemplate(label: "Bank"),
                    FieldTemplate(label: "Account Number", kind: .number, isConcealed: true),
                    FieldTemplate(label: "Sort Code", kind: .number),
                    FieldTemplate(label: "IBAN", isConcealed: true),
                    FieldTemplate(label: "Phone", kind: .phone),
                ], order: 2, modified: now),
            VaultGroup(
                name: "Software Licences", icon: "key",
                fields: [
                    FieldTemplate(label: "Licence Key", isConcealed: true),
                    FieldTemplate(label: "Registered To"),
                    FieldTemplate(label: "Email", kind: .email),
                    FieldTemplate(label: "Download", kind: .url),
                ], order: 3, modified: now),
            VaultGroup(
                name: "Secure Notes", icon: "note.text", fields: [], order: 4, modified: now),
        ]
    }
}
