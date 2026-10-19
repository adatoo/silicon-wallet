import Foundation

/// Every genuine SQLite 3 file starts with this 16-byte magic.
private let sqliteMagic: [UInt8] = Array("SQLite format 3\0".utf8)

/// Decrypts an Acrylic Wallet 3.5 `.wallet` file into an ordinary, unencrypted SQLite image.
///
/// This is only ever held in memory; Silicon Wallet never writes an imported vault's plaintext
/// to disk (DESIGN.md §5). See `AcrylicWalletReader` to query the result.
public enum AcrylicWalletFile {
    /// Decrypts `ciphertext`, trying the password as typed and then its NFC and NFD forms, so
    /// an accented password still opens a vault whose password was entered the other way.
    public static func decrypt(_ ciphertext: Data, password: String) throws -> Data {
        let bytes = [UInt8](ciphertext)
        let pageSize = try pageSize(ofHeader: bytes)
        guard bytes.count % pageSize == 0 else {
            throw AcrylicWalletError.notAnAcrylicWallet
        }

        for candidate in passwordForms(password) {
            do {
                return try decrypt(bytes, pageSize: pageSize, key: AcrylicWalletCipher.key(password: candidate))
            } catch AcrylicWalletError.wrongPasswordOrUnsupportedFile {
                continue
            }
        }
        throw AcrylicWalletError.wrongPasswordOrUnsupportedFile
    }

    /// Reads the page size from the header fields SEE leaves unencrypted (bytes 16–23), and
    /// rejects layouts this reader can't decrypt.
    static func pageSize(ofHeader bytes: [UInt8]) throws -> Int {
        // A real header's bytes 21–23 are always 64, 32, 32 (SQLite's payload fractions), so a
        // file without them isn't a SQLite database, encrypted or not.
        guard bytes.count >= 512, bytes[21] == 64, bytes[22] == 32, bytes[23] == 32 else {
            throw AcrylicWalletError.notAnAcrylicWallet
        }
        let raw = Int(bytes[16]) << 8 | Int(bytes[17])
        let pageSize = raw == 1 ? 65536 : raw
        guard pageSize >= 512, pageSize & (pageSize - 1) == 0 else {
            throw AcrylicWalletError.notAnAcrylicWallet
        }
        // Reserved bytes at the end of each page hold an SEE nonce or MAC, which this reader's
        // fixed per-page IV doesn't account for.
        guard bytes[20] == 0 else {
            throw AcrylicWalletError.unsupportedFormat
        }
        return pageSize
    }

    /// The password as typed, then its NFC and NFD forms, without repeats. Swift's `==` treats
    /// canonically equivalent strings as equal, so this compares their UTF-8 bytes instead.
    static func passwordForms(_ password: String) -> [String] {
        var forms: [String] = []
        for form in [
            password, password.precomposedStringWithCanonicalMapping, password.decomposedStringWithCanonicalMapping,
        ] where !forms.contains(where: { $0.utf8.elementsEqual(form.utf8) }) {
            forms.append(form)
        }
        return forms
    }

    private static func decrypt(_ bytes: [UInt8], pageSize: Int, key: [UInt8]) throws -> Data {
        let pageCount = bytes.count / pageSize

        var plaintext = [UInt8]()
        plaintext.reserveCapacity(bytes.count)

        for index in 0..<pageCount {
            let pageNumber = UInt32(index + 1)
            let start = index * pageSize
            let page = Array(bytes[start..<start + pageSize])
            let decryptedPage = try AcrylicWalletCipher.decryptPage(page, pageNumber: pageNumber, key: key)

            if pageNumber == 1, !decryptedPage.starts(with: sqliteMagic) {
                throw AcrylicWalletError.wrongPasswordOrUnsupportedFile
            }
            plaintext.append(contentsOf: decryptedPage)
        }

        return Data(plaintext)
    }
}
