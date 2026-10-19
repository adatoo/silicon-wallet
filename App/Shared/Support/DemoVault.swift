import Foundation
import SiliconWalletKit

/// Obviously fake entries for previews, UI tests and App Store screenshots (launch arguments
/// `-InMemoryVault -DemoVault`). Never used for a real vault.
@MainActor
enum DemoVault {
    static let password = "demo-password"

    static func fill(_ session: VaultSession) async throws {
        try await session.createVault(password: password, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
        func group(_ name: String) throws -> VaultGroup {
            guard let group = session.groups.first(where: { $0.name == name }) else { throw VaultError.notFound }
            return group
        }

        let logins = try group("Logins")
        let cards = try group("Credit Cards")
        let banks = try group("Bank Accounts")
        let licences = try group("Software Licences")
        let notes = try group("Secure Notes")

        func values(_ group: VaultGroup, _ values: [String]) -> [UUID: String] {
            Dictionary(uniqueKeysWithValues: zip(group.fields.map(\.id), values).filter { !$0.1.isEmpty })
        }

        try session.addEntry(
            VaultEntry(
                groupID: logins.id, title: "Example Mail",
                values: values(
                    logins, ["jane.appleseed@example.com", "correct-horse-battery-staple", "mail.example.com"]),
                isFavorite: true))
        try session.addEntry(
            VaultEntry(
                groupID: logins.id, title: "Example Shop",
                values: values(logins, ["jane.appleseed", "Shop-Demo-Pass-42", "shop.example.com"])))
        try session.addEntry(
            VaultEntry(
                groupID: logins.id, title: "Example Streaming",
                values: values(logins, ["jane@example.com", "s7r3am!ng-demo", "watch.example.com"]),
                notes: "Family plan renews in March."))
        try session.addEntry(
            VaultEntry(
                groupID: cards.id, title: "Example Visa",
                values: values(cards, ["Jane Appleseed", "4111 1111 1111 1111", "12/30", "123", "0000"]),
                isFavorite: true))
        try session.addEntry(
            VaultEntry(
                groupID: banks.id, title: "Example Bank",
                values: values(
                    banks,
                    ["Example Bank plc", "00000000", "00-00-00", "GB00 EXMP 0000 0000 0000 00", "+44 20 0000 0000"]))
        )
        try session.addEntry(
            VaultEntry(
                groupID: licences.id, title: "Example Photo Editor",
                values: values(
                    licences, ["DEMO-XXXX-YYYY-ZZZZ", "Jane Appleseed", "jane@example.com", "example.com/download"])))
        try session.addEntry(
            VaultEntry(
                groupID: notes.id, title: "Wi-Fi at Home",
                extraFields: [
                    CustomField(label: "Network", value: "Appleseed-Home"),
                    CustomField(label: "Password", kind: .password, value: "demo-wifi-passphrase"),
                ],
                notes: "Router is in the hall cupboard."))
        try session.addEntry(
            VaultEntry(
                groupID: notes.id, title: "Gym Locker",
                extraFields: [CustomField(label: "Code", kind: .number, isConcealed: true, value: "0000")]))
        try session.addEntry(
            VaultEntry(
                groupID: notes.id, title: "Library Card",
                extraFields: [CustomField(label: "Card Number", value: "EXAMPLE-0000")]))
        try session.addEntry(
            VaultEntry(
                groupID: notes.id, title: "4G Hotspot",
                extraFields: [
                    CustomField(label: "Network", value: "Example-Hotspot"),
                    CustomField(label: "Password", kind: .password, value: "demo-hotspot-pass"),
                ]))
    }
}
