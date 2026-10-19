import CommonCrypto
import Foundation

/// The per-page cipher used by Acrylic Wallet 3.5's `.wallet` files: the SQLite Encryption
/// Extension's AES-256-OFB variant, keyed from the vault password with no per-file salt.
///
/// Recovered by black-box known-plaintext analysis of fake fixtures only
/// (docs/adr/0005-acrylic-import-route.md, Fixtures/AcrylicWallet/README.md). This uses
/// CommonCrypto, Apple's system crypto library; no SEE source, no disassembly and no Acrylic
/// code were used, and none of this is loaded into Silicon Wallet's own vault format.
enum AcrylicWalletCipher {
    /// Bytes 16–23 of page 1 are the plaintext SQLite header fields (page size, format
    /// numbers, reserved-byte count). SEE never encrypts them.
    static let plainHeaderRange = 16..<24

    private static let keyPrefix = Array("W7f@".utf8)

    /// The 32-byte AES-256 key: `"W7f@" + password`, UTF-8, repeated/truncated to 32 bytes.
    /// This is SQLite's own `-key` rule (repeat short key material, truncate long material);
    /// there is no hash and no per-file salt.
    static func key(password: String) -> [UInt8] {
        var material = keyPrefix + Array(password.utf8)
        while material.count < 32 {
            material += material
        }
        return Array(material.prefix(32))
    }

    /// The IV for one page: its 1-based page number as a little-endian `UInt32`, zero-padded
    /// to 16 bytes.
    static func iv(pageNumber: UInt32) -> [UInt8] {
        let little = pageNumber.littleEndian
        var bytes = [UInt8](repeating: 0, count: 16)
        withUnsafeBytes(of: little) { raw in
            for offset in 0..<4 {
                bytes[offset] = raw[offset]
            }
        }
        return bytes
    }

    /// Decrypts one whole page with AES-256-OFB. `pageNumber` is 1-based, matching SQLite's
    /// own page numbering. For page 1, the unencrypted header bytes are restored from the
    /// ciphertext afterwards. OFB is symmetric, so this also encrypts a plaintext page.
    static func decryptPage(_ ciphertext: [UInt8], pageNumber: UInt32, key: [UInt8]) throws -> [UInt8] {
        let pageSize = ciphertext.count
        guard pageSize >= plainHeaderRange.upperBound else {
            throw AcrylicWalletError.notAnAcrylicWallet
        }

        var cryptor: CCCryptorRef?
        let ivBytes = iv(pageNumber: pageNumber)
        let createStatus = CCCryptorCreateWithMode(
            CCOperation(kCCDecrypt),
            CCMode(kCCModeOFB),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            ivBytes,
            key,
            key.count,
            nil,
            0,
            0,
            CCModeOptions(0),
            &cryptor
        )
        guard createStatus == CCCryptorStatus(kCCSuccess), let cryptor else {
            throw AcrylicWalletError.cipherFailed(Int(createStatus))
        }
        defer { CCCryptorRelease(cryptor) }

        var plaintext = [UInt8](repeating: 0, count: pageSize)
        var moved = 0
        let updateStatus = CCCryptorUpdate(
            cryptor,
            ciphertext,
            ciphertext.count,
            &plaintext,
            plaintext.count,
            &moved
        )
        guard updateStatus == CCCryptorStatus(kCCSuccess), moved == pageSize else {
            throw AcrylicWalletError.cipherFailed(Int(updateStatus))
        }

        if pageNumber == 1 {
            plaintext.replaceSubrange(plainHeaderRange, with: ciphertext[plainHeaderRange])
        }
        return plaintext
    }
}
