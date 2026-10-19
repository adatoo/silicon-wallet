import Clibsodium
import CryptoKit
import Foundation

/// The Argon2id settings for one vault, stored with it in the clear so any device can derive
/// the same KEK (DESIGN.md §5).
public struct KDFParameters: Codable, Equatable, Sendable {
    public enum Algorithm: String, Codable, Sendable {
        /// Argon2id, version 1.3 (libsodium's `crypto_pwhash_ALG_ARGON2ID13`).
        case argon2id13
    }

    public static let saltLength = 16
    /// The starting point from DESIGN.md §5: 64 MiB and 3 passes, to be tuned to about 0.5 s on
    /// the slowest supported device.
    public static let defaultMemoryBytes = 64 << 20
    public static let defaultIterations = 3
    /// The most this build will run. The parameters arrive with a synced `VaultMeta`, so without a
    /// ceiling a tampered meta could make every unlock hang or run out of memory.
    public static let maximumMemoryBytes = 1 << 30
    public static let maximumIterations = 20

    public var algorithm: Algorithm
    public var salt: Data
    public var iterations: Int
    public var memoryBytes: Int

    public init(algorithm: Algorithm = .argon2id13, salt: Data, iterations: Int, memoryBytes: Int) {
        self.algorithm = algorithm
        self.salt = salt
        self.iterations = iterations
        self.memoryBytes = memoryBytes
    }

    /// Whether this build accepts these parameters: the right algorithm and salt length, and
    /// limits between libsodium's minimums and this build's maximums.
    public var isWithinLimits: Bool {
        algorithm == .argon2id13 && salt.count == Self.saltLength
            && (Int(crypto_pwhash_opslimit_min())...Self.maximumIterations).contains(iterations)
            && (Int(crypto_pwhash_memlimit_min())...Self.maximumMemoryBytes).contains(memoryBytes)
    }

    /// New parameters with a random salt, for a new vault or a password change.
    public static func generate(
        iterations: Int = defaultIterations,
        memoryBytes: Int = defaultMemoryBytes
    ) -> KDFParameters {
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return KDFParameters(salt: salt, iterations: iterations, memoryBytes: memoryBytes)
    }
}

/// Master password → KEK, with Argon2id from libsodium.
public enum KeyDerivation {
    private static let sodiumReady: Bool = sodium_init() >= 0

    /// Derives the 256-bit key-encryption key that wraps the vault key.
    ///
    /// The password is normalised to Unicode NFC first, so the same password typed on
    /// different devices or keyboards (precomposed `ä` or `a` plus a combining diaeresis)
    /// always derives the same key.
    public static func deriveKEK(password: String, parameters: KDFParameters) throws -> SymmetricKey {
        guard sodiumReady else { throw CryptoError.keyDerivationFailed }
        guard parameters.isWithinLimits else { throw CryptoError.invalidParameters }

        // A trailing NUL keeps the buffer non-empty, so it always has an address; it isn't
        // part of the length passed to Argon2id.
        var passwordBytes = Array(password.precomposedStringWithCanonicalMapping.utf8CString)
        let passwordLength = passwordBytes.count - 1
        var output = [UInt8](repeating: 0, count: 32)
        defer {
            sodium_memzero(&passwordBytes, passwordBytes.count)
            sodium_memzero(&output, output.count)
        }

        let status = parameters.salt.withUnsafeBytes { salt -> Int32 in
            passwordBytes.withUnsafeBufferPointer { password -> Int32 in
                guard let password = password.baseAddress,
                    let salt = salt.bindMemory(to: UInt8.self).baseAddress
                else { return -1 }
                return crypto_pwhash(
                    &output,
                    UInt64(output.count),
                    password,
                    UInt64(passwordLength),
                    salt,
                    UInt64(parameters.iterations),
                    parameters.memoryBytes,
                    crypto_pwhash_alg_argon2id13()
                )
            }
        }
        guard status == 0 else { throw CryptoError.keyDerivationFailed }
        return SymmetricKey(data: output)
    }
}
