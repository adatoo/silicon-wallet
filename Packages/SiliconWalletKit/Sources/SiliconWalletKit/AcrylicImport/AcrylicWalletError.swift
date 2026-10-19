/// Errors from reading an Acrylic Wallet 3.5 `.wallet` file.
public enum AcrylicWalletError: Error, Equatable, Sendable {
    /// The file lacks the plaintext SQLite header fields SEE leaves in place, or its size
    /// isn't a whole number of pages, so it isn't an Acrylic Wallet file.
    case notAnAcrylicWallet
    /// The header is a valid SEE one, but uses a layout this reader doesn't decrypt (reserved
    /// bytes per page, for an SEE nonce or MAC). Probably a different Wallet version.
    case unsupportedFormat
    /// Page 1 didn't decrypt to a valid SQLite header. Almost always a wrong password;
    /// could also be a file this reader doesn't support.
    case wrongPasswordOrUnsupportedFile
    /// A CommonCrypto call failed; the `CCCryptorStatus` is included for diagnostics.
    case cipherFailed(Int)
    /// The decrypted bytes don't open as SQLite, or fail `PRAGMA integrity_check`, or a table the
    /// reader needs is missing or isn't a plain table.
    case corruptDatabase
    /// The file is larger than `AcrylicWalletFile.maximumFileSize`.
    case fileTooLarge
}
