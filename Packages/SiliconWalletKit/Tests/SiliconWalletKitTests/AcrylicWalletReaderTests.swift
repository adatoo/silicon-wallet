import CryptoKit
import Foundation
import SQLite3
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

/// f.wallet's password was pasted, so it's precomposed (NFC). Typed as decomposed letters
/// plus combining marks (NFD), it's different bytes but must still open the vault.
@Test func aDecomposedPasswordOpensAPrecomposedVault() throws {
    let decomposed = "fake-pa\u{0308}sswo\u{0308}rd-\u{2713}"
    #expect(!decomposed.utf8.elementsEqual("fake-pässwörd-✓".utf8))

    let reader = try AcrylicWalletReader(ciphertext: Fixture.data("f.wallet"), password: decomposed)
    #expect(try reader.entries().count == 2)
}

@Test func passwordFormsSkipRepeats() {
    #expect(AcrylicWalletFile.passwordForms("fakepass") == ["fakepass"])
    #expect(AcrylicWalletFile.passwordForms("fake-pässwörd").count == 2)
}

/// Wallet 3.5 always uses 1024-byte pages, but the page size comes from the header, so a
/// file with bigger pages decrypts too. The fake vault is built here: a plain SQLite image,
/// encrypted page by page with the same cipher (OFB is symmetric).
@Test func aVaultWithBiggerPagesDecrypts() throws {
    let plaintext = try syntheticVault(pageSize: 4096)
    let ciphertext = try encrypt(plaintext, pageSize: 4096, password: "fakepass-4096")

    let reader = try AcrylicWalletReader(ciphertext: ciphertext, password: "fakepass-4096")
    #expect(try reader.groups().map(\.title) == ["Fake Group"])
    #expect(try reader.entries().map(\.title) == ["Fake Entry"])
}

@Test func reservedBytesPerPageAreUnsupported() throws {
    var ciphertext = try Fixture.data("a.wallet")
    ciphertext[20] = 12

    #expect(throws: AcrylicWalletError.unsupportedFormat) {
        try AcrylicWalletReader(ciphertext: ciphertext, password: "fakepass")
    }
}

@Test func aFileThatIsNotSQLiteIsRejected() throws {
    var notAVault = try Fixture.data("attachment-test.png")
    notAVault.append(Data(count: 1024 - notAVault.count % 1024))

    #expect(throws: AcrylicWalletError.notAnAcrylicWallet) {
        try AcrylicWalletReader(ciphertext: notAVault, password: "fakepass")
    }
}

/// A plain SQLite image with the tables and columns `AcrylicWalletReader` queries, one fake
/// group and one fake entry, at the given page size.
private func syntheticVault(pageSize: Int) throws -> Data {
    var db: OpaquePointer?
    try #require(sqlite3_open(":memory:", &db) == SQLITE_OK)
    defer { sqlite3_close(db) }

    let sql = """
        PRAGMA page_size = \(pageSize);
        CREATE TABLE groups (pk INTEGER PRIMARY KEY, title TEXT, icon TEXT, "order" INTEGER, uuid TEXT,
            defaultheaders BLOB, datelastupdated TEXT);
        CREATE TABLE entries (pk INTEGER PRIMARY KEY, title TEXT, parent TEXT, notes TEXT, infodictionary TEXT,
            extraheaders BLOB, star INTEGER, uuid TEXT, files TEXT, datelastupdated TEXT);
        CREATE TABLE files (pk INTEGER PRIMARY KEY, uuid TEXT, name TEXT, size INTEGER, type TEXT, data BLOB);
        INSERT INTO groups (title, "order", uuid) VALUES ('Fake Group', 0, 'FAKE-GROUP');
        INSERT INTO entries (title, parent, star, uuid) VALUES ('Fake Entry', 'FAKE-GROUP', 0, 'FAKE-ENTRY');
        """
    try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)

    var size: sqlite3_int64 = 0
    let bytes = try #require(sqlite3_serialize(db, "main", &size, 0))
    defer { sqlite3_free(bytes) }
    let image = Data(bytes: bytes, count: Int(size))
    try #require(image.count % pageSize == 0 && image.count > pageSize)
    return image
}

private func encrypt(_ plaintext: Data, pageSize: Int, password: String) throws -> Data {
    let key = AcrylicWalletCipher.key(password: password)
    let bytes = [UInt8](plaintext)
    var ciphertext = Data()
    for start in stride(from: 0, to: bytes.count, by: pageSize) {
        let page = Array(bytes[start..<start + pageSize])
        let pageNumber = UInt32(start / pageSize + 1)
        ciphertext.append(contentsOf: try AcrylicWalletCipher.decryptPage(page, pageNumber: pageNumber, key: key))
    }
    return ciphertext
}

// MARK: - Hostile files

/// A plain SQLite image built from `sql`, as a decrypted Wallet file would be.
private func sqliteImage(_ sql: String) throws -> Data {
    var db: OpaquePointer?
    guard sqlite3_open(":memory:", &db) == SQLITE_OK, let db else { throw AcrylicWalletError.corruptDatabase }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw AcrylicWalletError.corruptDatabase }
    var size: sqlite3_int64 = 0
    guard let bytes = sqlite3_serialize(db, "main", &size, 0) else { throw AcrylicWalletError.corruptDatabase }
    defer { sqlite3_free(bytes) }
    return Data(bytes: bytes, count: Int(size))
}

@Test func aFileOverTheSizeLimitIsRefusedBeforeDecrypting() throws {
    let file = try Fixture.data("a.wallet")
    #expect(throws: AcrylicWalletError.fileTooLarge) {
        try AcrylicWalletFile.decrypt(file, password: "fakepass", maximumSize: file.count - 1)
    }
    #expect(AcrylicWalletFile.maximumFileSize == 512 * 1024 * 1024)
}

@Test func aViewInPlaceOfATableIsRejected() throws {
    let tables = "CREATE TABLE entries (pk INTEGER); CREATE TABLE files (pk INTEGER);"
    let withView = try sqliteImage(
        tables
            + """
             CREATE VIEW groups AS WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n)
             SELECT x AS pk FROM n;
            """)
    #expect(throws: AcrylicWalletError.corruptDatabase) { try AcrylicWalletReader(plaintext: withView) }

    let missing = try sqliteImage(tables)
    #expect(throws: AcrylicWalletError.corruptDatabase) { try AcrylicWalletReader(plaintext: missing) }

    let plain = try sqliteImage(tables + " CREATE TABLE groups (pk INTEGER);")
    #expect(try AcrylicWalletReader(plaintext: plain).groups().isEmpty)
}
