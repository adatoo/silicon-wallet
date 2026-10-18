/// Errors from the vault's crypto (DESIGN.md §5).
public enum CryptoError: Error, Equatable, Sendable {
    /// The KDF parameters are outside what this build accepts, or the salt has the wrong length.
    case invalidParameters
    /// Argon2id failed to run, almost always because the memory limit couldn't be allocated.
    case keyDerivationFailed
    /// AES-GCM authentication failed: a wrong password or key, tampered bytes, or a sealed
    /// value opened under the wrong record or attachment ID. The cases are deliberately not
    /// told apart.
    case authenticationFailed
    /// The envelope is too short to hold a version byte, nonce and tag.
    case truncatedEnvelope
    /// The envelope was written by a format version this build doesn't read.
    case unsupportedVersion(UInt8)
}
