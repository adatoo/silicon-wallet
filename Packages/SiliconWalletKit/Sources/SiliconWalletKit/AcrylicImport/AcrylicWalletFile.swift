import Foundation

/// Every genuine SQLite 3 file starts with this 16-byte magic.
private let sqliteMagic: [UInt8] = Array("SQLite format 3\0".utf8)

/// Decrypts an Acrylic Wallet 3.5 `.wallet` file into an ordinary, unencrypted SQLite image.
///
/// This is only ever held in memory; Silicon Wallet never writes an imported vault's plaintext
/// to disk (DESIGN.md §5). See `AcrylicWalletReader` to query the result.
public enum AcrylicWalletFile {
    public static func decrypt(_ ciphertext: Data, password: String) throws -> Data {
        guard !ciphertext.isEmpty, ciphertext.count % AcrylicWalletCipher.pageSize == 0 else {
            throw AcrylicWalletError.notAnAcrylicWallet
        }

        let key = AcrylicWalletCipher.key(password: password)
        let bytes = [UInt8](ciphertext)
        let pageCount = bytes.count / AcrylicWalletCipher.pageSize

        var plaintext = [UInt8]()
        plaintext.reserveCapacity(bytes.count)

        for index in 0..<pageCount {
            let pageNumber = UInt32(index + 1)
            let start = index * AcrylicWalletCipher.pageSize
            let end = start + AcrylicWalletCipher.pageSize
            let page = Array(bytes[start..<end])
            let decryptedPage = try AcrylicWalletCipher.decryptPage(page, pageNumber: pageNumber, key: key)

            if pageNumber == 1, !decryptedPage.starts(with: sqliteMagic) {
                throw AcrylicWalletError.wrongPasswordOrUnsupportedFile
            }
            plaintext.append(contentsOf: decryptedPage)
        }

        return Data(plaintext)
    }
}
