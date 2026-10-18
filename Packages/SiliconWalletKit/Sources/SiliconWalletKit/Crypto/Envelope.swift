import CryptoKit
import Foundation

/// The one sealed-value format behind the vault key, records and attachments:
///
///     version (1 byte) ‖ nonce (12) ‖ ciphertext ‖ tag (16)
///
/// AES-256-GCM with a random nonce. The associated data binds the version, what the value is
/// for, and, for records and attachments, the owning ID, so a sealed value can't be replayed
/// as a different kind of value or under a different ID.
enum Envelope {
    static let version: UInt8 = 1
    static let nonceLength = 12
    static let tagLength = 16
    static let overhead = 1 + nonceLength + tagLength

    /// What a sealed value is, mixed into the associated data.
    enum Purpose: String {
        case vaultKey = "vault-key"
        case record
        case attachment
    }

    static func associatedData(_ purpose: Purpose, id: UUID?) -> Data {
        var aad = Data([version])
        aad.append(contentsOf: "SiliconWallet/\(purpose.rawValue)".utf8)
        if let id {
            aad.append(0)
            withUnsafeBytes(of: id.uuid) { aad.append(contentsOf: $0) }
        }
        return aad
    }

    /// `nonce` is for known-answer tests only; real callers always get a random one.
    static func seal(
        _ plaintext: Data,
        key: SymmetricKey,
        purpose: Purpose,
        id: UUID?,
        nonce: AES.GCM.Nonce = AES.GCM.Nonce()
    ) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext, using: key, nonce: nonce, authenticating: associatedData(purpose, id: id))
        guard let combined = box.combined else { throw CryptoError.authenticationFailed }
        return Data([version]) + combined
    }

    static func open(_ envelope: Data, key: SymmetricKey, purpose: Purpose, id: UUID?) throws -> Data {
        guard envelope.count >= overhead else { throw CryptoError.truncatedEnvelope }
        let found = envelope[envelope.startIndex]
        guard found == version else { throw CryptoError.unsupportedVersion(found) }

        do {
            let box = try AES.GCM.SealedBox(combined: envelope.dropFirst())
            return try AES.GCM.open(box, using: key, authenticating: associatedData(purpose, id: id))
        } catch {
            throw CryptoError.authenticationFailed
        }
    }
}
