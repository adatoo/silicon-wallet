import CryptoKit
import Foundation

/// The vault key: random, 256-bit, made once per vault and stored only wrapped under the KEK.
/// Changing the master password re-wraps it; nothing else changes (DESIGN.md §5).
public enum VaultKey {
    public static func generate() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    public static func wrap(_ vaultKey: SymmetricKey, kek: SymmetricKey) throws -> Data {
        try vaultKey.withUnsafeBytes { raw in
            try Envelope.seal(Data(raw), key: kek, purpose: .vaultKey, id: nil)
        }
    }

    /// Throws `CryptoError.authenticationFailed` for a wrong master password.
    public static func unwrap(_ wrapped: Data, kek: SymmetricKey) throws -> SymmetricKey {
        var raw = try Envelope.open(wrapped, key: kek, purpose: .vaultKey, id: nil)
        defer { raw.resetBytes(in: raw.startIndex..<raw.endIndex) }
        guard raw.count == 32 else { throw CryptoError.authenticationFailed }
        return SymmetricKey(data: raw)
    }

    /// A small sealed value that proves a key is this vault's vault key, so a key from the
    /// biometric Keychain item can be checked before it's trusted.
    public static func makeCheck(for vaultKey: SymmetricKey) throws -> Data {
        try Envelope.seal(Data(), key: vaultKey, purpose: .keyCheck, id: nil)
    }

    public static func verify(_ vaultKey: SymmetricKey, check: Data) -> Bool {
        (try? Envelope.open(check, key: vaultKey, purpose: .keyCheck, id: nil)) != nil
    }
}

/// Seals each Group and Entry payload under the vault key, with its record ID as associated
/// data, so ciphertext can't be moved between records.
public enum RecordSealer {
    public static func seal(_ plaintext: Data, recordID: UUID, key: SymmetricKey) throws -> Data {
        try Envelope.seal(plaintext, key: key, purpose: .record, id: recordID)
    }

    public static func open(_ envelope: Data, recordID: UUID, key: SymmetricKey) throws -> Data {
        try Envelope.open(envelope, key: key, purpose: .record, id: recordID)
    }
}

/// Seals attachment files. Each file has its own random key, which is kept inside the owning
/// Entry's encrypted payload (`AttachmentRef.fileKey`), never on its own.
public enum AttachmentSealer {
    public static func generateFileKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    public static func seal(_ contents: Data, attachmentID: UUID, fileKey: SymmetricKey) throws -> Data {
        try Envelope.seal(contents, key: fileKey, purpose: .attachment, id: attachmentID)
    }

    public static func open(_ envelope: Data, attachmentID: UUID, fileKey: SymmetricKey) throws -> Data {
        try Envelope.open(envelope, key: fileKey, purpose: .attachment, id: attachmentID)
    }
}
