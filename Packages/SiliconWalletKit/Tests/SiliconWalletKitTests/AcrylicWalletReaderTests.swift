import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests against the fake Acrylic Wallet fixtures in `Fixtures/AcrylicWallet/`
/// (docs/adr/0005-acrylic-import-route.md). Everything in that folder is fake data made for
/// this spike; none of it is a real vault.
private enum Fixture {
    /// `Fixtures/AcrylicWallet/`, four levels above this test file
    /// (Tests/SiliconWalletKitTests -> Tests -> SiliconWalletKit -> Packages -> repo root).
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AcrylicWallet")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

@Test func aWalletDecryptsWithItsFakePassword() throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data("a.wallet"), password: "fakepass")
    let groups = try reader.groups()
    let entries = try reader.entries()

    #expect(
        groups.map(\.title).sorted() == [
            "Credit Cards", "Fake Accounts", "Fake Logins", "Serial Numbers", "Web Passwords",
        ])
    #expect(entries.count == 5)

    let bank = try #require(entries.first { $0.title == "Example Bank" })
    #expect(bank.isStarred)
    #expect(bank.fieldValues.values.contains("fake.user@example.com"))

    let shop = try #require(entries.first { $0.title == "Example Shop" })
    #expect(!shop.isStarred)
}

@Test func bWalletSharesAPasswordButNoEntriesWithA() throws {
    let a = try AcrylicWalletReader(ciphertext: Fixture.data("a.wallet"), password: "fakepass")
    let b = try AcrylicWalletReader(ciphertext: Fixture.data("b.wallet"), password: "fakepass")

    let aTitles = Set(try a.entries().map(\.title))
    let bEntries = try b.entries()

    #expect(bEntries.count == 5)
    #expect(aTitles.isDisjoint(with: bEntries.map(\.title)))
}

@Test(
    arguments: [
        ("c.wallet", "fakepass1234"),
        ("d.wallet", "fakepass12XY"),
        ("e.wallet", "fakepass-fakepass-fakepass-fakepass-1234"),
        ("f.wallet", "fake-pässwörd-✓"),
    ]
)
func smallVaultsDecryptWithTheirFakePassword(name: String, password: String) throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data(name), password: password)
    #expect(try reader.entries().count == 2)
}

/// h.wallet was created with a different password, then changed to its final one: a re-key,
/// not a copy. It has the same contents as a.wallet, re-entered by hand rather than copied.
@Test func hWalletIsARekeyedCopyOfA() throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data("h.wallet"), password: "fakepass-2")
    let entries = try reader.entries()

    #expect(entries.count == 5)
    let bank = try #require(entries.first { $0.title == "Example Bank" })
    #expect(bank.isStarred)
}

@Test func gWalletHasTheAttachmentAndManyEntries() throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data("g.wallet"), password: "fakepass")
    let entries = try reader.entries()
    let files = try reader.files()

    #expect(entries.count == 32)
    #expect(files.count == 1)

    let attachment = try #require(files.first)
    let decryptedDigest = SHA256.hash(data: attachment.data)
    let originalDigest = SHA256.hash(data: try Fixture.data("attachment-test.png"))
    #expect(decryptedDigest == originalDigest)
}

@Test func iWalletHasTheCardAndPasswordFieldsInPlainText() throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data("i.wallet"), password: "fakepassword")
    let entries = try reader.entries()

    let allValues = Set(entries.flatMap(\.fieldValues.values))
    #expect(allValues.contains("4111 1111 1111 1111"))
    #expect(allValues.contains("fakepassword"))
    #expect(allValues.contains("fakeuser"))
}

@Test(arguments: [
    ("a-export.wallet", "fakepass", 5), ("g-export.wallet", "fakepass", 32), ("i-export.wallet", "fakepassword", 2),
])
func exportsDecryptWithTheSamePasswordAsTheirSourceVault(name: String, password: String, entryCount: Int) throws {
    let reader = try AcrylicWalletReader(ciphertext: Fixture.data(name), password: password)
    #expect(try reader.entries().count == entryCount)
}

@Test func wrongPasswordIsRejected() throws {
    #expect(throws: AcrylicWalletError.wrongPasswordOrUnsupportedFile) {
        try AcrylicWalletReader(ciphertext: try Fixture.data("a.wallet"), password: "not-the-fake-password")
    }
}
