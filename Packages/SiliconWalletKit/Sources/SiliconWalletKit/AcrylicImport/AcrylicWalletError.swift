/// Errors from reading an Acrylic Wallet 3.5 `.wallet` file.
public enum AcrylicWalletError: Error, Equatable, Sendable {
    /// The file's size isn't a whole number of 1024-byte pages, so it isn't an Acrylic
    /// Wallet 3.5 file (or a different page size than the fixtures used).
    case notAnAcrylicWallet
    /// Page 1 didn't decrypt to a valid SQLite header. Almost always a wrong password;
    /// could also be a file this reader doesn't support.
    case wrongPasswordOrUnsupportedFile
    /// A CommonCrypto call failed; the `CCCryptorStatus` is included for diagnostics.
    case cipherFailed(Int)
    /// The decrypted bytes don't open as SQLite, or fail `PRAGMA integrity_check`.
    case corruptDatabase
}
