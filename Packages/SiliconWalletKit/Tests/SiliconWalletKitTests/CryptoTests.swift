import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for the key hierarchy in DESIGN.md §5. Every password and key here is fake.
private enum Vector {
    static let salt = Data(0..<16)
    /// libsodium's minimum memory and passes: fast, for tests that aren't about the KDF itself.
    static let fastParameters = KDFParameters(salt: salt, iterations: 1, memoryBytes: 8 << 10)

    static func hex(_ string: String) -> Data {
        var data = Data()
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            data.append(UInt8(string[index..<next], radix: 16)!)
            index = next
        }
        return data
    }

    static func bytes(_ key: SymmetricKey) -> Data {
        key.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Argon2id

/// Known-answer vectors from an independent Argon2id implementation, OpenSSL 3.6's `ARGON2ID`
/// KDF (`openssl kdf -keylen 32 -kdfopt pass:… -kdfopt hexsalt:000102…0f -kdfopt iter:… -kdfopt
/// memcost:<KiB> -kdfopt lanes:1 -kdfopt threads:1 ARGON2ID`), which reproduces the reference
/// implementation's own argon2id vector (`password`/`somesalt`, t=2, m=64 MiB, p=1).
@Test func argon2idMatchesTheIndependentVectorAtTheDefaultParameters() throws {
    let parameters = KDFParameters(salt: Vector.salt, iterations: 3, memoryBytes: 64 << 20)
    let kek = try KeyDerivation.deriveKEK(password: "fake-master-password", parameters: parameters)
    #expect(Vector.bytes(kek) == Vector.hex("6f93f984646c37129c587950b659be715e33510ce52a46bcf08653090d8b8781"))
}

@Test func argon2idMatchesTheIndependentVectorForANonASCIIPassword() throws {
    let kek = try KeyDerivation.deriveKEK(
        password: "fake-p\u{E4}ssw\u{F6}rd-\u{2713}", parameters: Vector.fastParameters)
    #expect(Vector.bytes(kek) == Vector.hex("41b52dee4a361dc4257453611a0daac341fb783eaa16101a26ca0c56e72b6379"))
}

@Test func decomposedAndPrecomposedPasswordsDeriveTheSameKey() throws {
    let precomposed = "fake-p\u{E4}ssw\u{F6}rd-\u{2713}"
    let decomposed = "fake-pa\u{308}sswo\u{308}rd-\u{2713}"
    #expect(Array(precomposed.utf8) != Array(decomposed.utf8))

    let a = try KeyDerivation.deriveKEK(password: precomposed, parameters: Vector.fastParameters)
    let b = try KeyDerivation.deriveKEK(password: decomposed, parameters: Vector.fastParameters)
    #expect(Vector.bytes(a) == Vector.bytes(b))
}

@Test func differentSaltsDeriveDifferentKeys() throws {
    var other = Vector.fastParameters
    other.salt = Data(repeating: 0xAA, count: 16)
    let a = try KeyDerivation.deriveKEK(password: "fakepass", parameters: Vector.fastParameters)
    let b = try KeyDerivation.deriveKEK(password: "fakepass", parameters: other)
    #expect(Vector.bytes(a) != Vector.bytes(b))
}

@Test func generatedParametersHaveARandomSaltAndTheDefaults() {
    let a = KDFParameters.generate()
    let b = KDFParameters.generate()
    #expect(a.salt.count == 16)
    #expect(a.salt != b.salt)
    #expect(a.iterations == 3)
    #expect(a.memoryBytes == 64 << 20)
}

@Test func badKDFParametersAreRejected() {
    var shortSalt = Vector.fastParameters
    shortSalt.salt = Data(count: 8)
    var tooLittleMemory = Vector.fastParameters
    tooLittleMemory.memoryBytes = 1024
    var noPasses = Vector.fastParameters
    noPasses.iterations = 0
    // A tampered synced VaultMeta could ask for these; they'd hang or exhaust memory.
    var tooMuchMemory = Vector.fastParameters
    tooMuchMemory.memoryBytes = 4 << 30
    var tooManyPasses = Vector.fastParameters
    tooManyPasses.iterations = 1_000_000

    for parameters in [shortSalt, tooLittleMemory, noPasses, tooMuchMemory, tooManyPasses] {
        #expect(!parameters.isWithinLimits)
        #expect(throws: CryptoError.invalidParameters) {
            try KeyDerivation.deriveKEK(password: "fakepass", parameters: parameters)
        }
    }
}

@Test func theDefaultsAndTheCeilingsAreWithinLimits() {
    #expect(KDFParameters.generate().isWithinLimits)
    #expect(
        KDFParameters.generate(
            iterations: KDFParameters.maximumIterations, memoryBytes: KDFParameters.maximumMemoryBytes
        )
        .isWithinLimits)
}

@Test func kdfParametersRoundTripThroughCodable() throws {
    let parameters = KDFParameters.generate()
    let decoded = try JSONDecoder().decode(KDFParameters.self, from: JSONEncoder().encode(parameters))
    #expect(decoded == parameters)
}

// MARK: - AES-GCM

/// The GCM specification's Test Case 16 (McGrew and Viega; AES-256, 96-bit IV, with associated
/// data), through CryptoKit, the primitive every envelope uses.
@Test func aesGCMMatchesTheSpecificationVector() throws {
    let key = SymmetricKey(data: Vector.hex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"))
    let nonce = try AES.GCM.Nonce(data: Vector.hex("cafebabefacedbaddecaf888"))
    let plaintext = Vector.hex(
        "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
            + "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
    let aad = Vector.hex("feedfacedeadbeeffeedfacedeadbeefabaddad2")

    let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
    #expect(
        box.ciphertext
            == Vector.hex(
                "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa"
                    + "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662"))
    #expect(box.tag == Vector.hex("76fc6ece0f4e1768cddf8853bb2d551b"))
}

// MARK: - Vault key

@Test func theVaultKeyRoundTripsUnderTheKEK() throws {
    let kek = try KeyDerivation.deriveKEK(password: "fakepass", parameters: Vector.fastParameters)
    let vaultKey = VaultKey.generate()
    let wrapped = try VaultKey.wrap(vaultKey, kek: kek)

    #expect(wrapped.count == Envelope.overhead + 32)
    #expect(Vector.bytes(try VaultKey.unwrap(wrapped, kek: kek)) == Vector.bytes(vaultKey))
}

@Test func aWrongPasswordCannotUnwrapTheVaultKey() throws {
    let kek = try KeyDerivation.deriveKEK(password: "fakepass", parameters: Vector.fastParameters)
    let wrong = try KeyDerivation.deriveKEK(password: "fakepass!", parameters: Vector.fastParameters)
    let wrapped = try VaultKey.wrap(VaultKey.generate(), kek: kek)

    #expect(throws: CryptoError.authenticationFailed) {
        try VaultKey.unwrap(wrapped, kek: wrong)
    }
}

@Test func generatedKeysAreRandom() {
    #expect(Vector.bytes(VaultKey.generate()) != Vector.bytes(VaultKey.generate()))
    #expect(Vector.bytes(AttachmentSealer.generateFileKey()) != Vector.bytes(AttachmentSealer.generateFileKey()))
    #expect(VaultKey.generate().bitCount == 256)
}

// MARK: - Records

@Test func aRecordRoundTrips() throws {
    let key = VaultKey.generate()
    let id = UUID()
    let plaintext = Data("Example Bank / fake.user@example.com".utf8)
    let sealed = try RecordSealer.seal(plaintext, recordID: id, key: key)

    #expect(sealed.first == Envelope.version)
    #expect(sealed.count == plaintext.count + Envelope.overhead)
    #expect(try RecordSealer.open(sealed, recordID: id, key: key) == plaintext)
}

@Test func sealingTwiceUsesDifferentNonces() throws {
    let key = VaultKey.generate()
    let id = UUID()
    let plaintext = Data("fake".utf8)
    #expect(
        try RecordSealer.seal(plaintext, recordID: id, key: key) != RecordSealer.seal(plaintext, recordID: id, key: key)
    )
}

@Test func aRecordCannotBeOpenedUnderAnotherRecordID() throws {
    let key = VaultKey.generate()
    let sealed = try RecordSealer.seal(Data("fake".utf8), recordID: UUID(), key: key)

    #expect(throws: CryptoError.authenticationFailed) {
        try RecordSealer.open(sealed, recordID: UUID(), key: key)
    }
}

@Test func aRecordCannotBeOpenedWithAnotherKey() throws {
    let id = UUID()
    let sealed = try RecordSealer.seal(Data("fake".utf8), recordID: id, key: VaultKey.generate())

    #expect(throws: CryptoError.authenticationFailed) {
        try RecordSealer.open(sealed, recordID: id, key: VaultKey.generate())
    }
}

@Test(arguments: [
    ("nonce", 1),
    ("ciphertext", 1 + Envelope.nonceLength),
    ("tag", -1),
])
func flippingAnyByteIsDetected(part: String, offset: Int) throws {
    let key = VaultKey.generate()
    let id = UUID()
    var sealed = try RecordSealer.seal(Data("fake secret".utf8), recordID: id, key: key)
    let index = offset >= 0 ? offset : sealed.count + offset
    sealed[index] ^= 0x01

    #expect(throws: CryptoError.authenticationFailed, "tampered \(part)") {
        try RecordSealer.open(sealed, recordID: id, key: key)
    }
}

@Test func truncatedEnvelopesAreRejected() throws {
    let key = VaultKey.generate()
    let id = UUID()
    let sealed = try RecordSealer.seal(Data("fake".utf8), recordID: id, key: key)

    #expect(throws: CryptoError.truncatedEnvelope) {
        try RecordSealer.open(sealed.prefix(Envelope.overhead - 1), recordID: id, key: key)
    }
    #expect(throws: CryptoError.authenticationFailed) {
        try RecordSealer.open(sealed.dropLast(), recordID: id, key: key)
    }
}

@Test func anUnknownVersionIsRejected() throws {
    let key = VaultKey.generate()
    let id = UUID()
    var sealed = try RecordSealer.seal(Data("fake".utf8), recordID: id, key: key)
    sealed[0] = 2

    #expect(throws: CryptoError.unsupportedVersion(2)) {
        try RecordSealer.open(sealed, recordID: id, key: key)
    }
}

/// A sealed value of one kind must never open as another, even under the same key and ID.
@Test func purposesDoNotCrossOver() throws {
    let key = VaultKey.generate()
    let id = UUID()
    let record = try RecordSealer.seal(Data(repeating: 0x42, count: 32), recordID: id, key: key)

    #expect(throws: CryptoError.authenticationFailed) {
        try AttachmentSealer.open(record, attachmentID: id, fileKey: key)
    }
    #expect(throws: CryptoError.authenticationFailed) {
        try VaultKey.unwrap(record, kek: key)
    }
}

// MARK: - Attachments

@Test func anAttachmentRoundTripsUnderItsOwnKey() throws {
    let fileKey = AttachmentSealer.generateFileKey()
    let id = UUID()
    let contents = Data(repeating: 0x5A, count: 100_000)
    let sealed = try AttachmentSealer.seal(contents, attachmentID: id, fileKey: fileKey)

    #expect(try AttachmentSealer.open(sealed, attachmentID: id, fileKey: fileKey) == contents)
    #expect(throws: CryptoError.authenticationFailed) {
        try AttachmentSealer.open(sealed, attachmentID: UUID(), fileKey: fileKey)
    }
}

// MARK: - Format regression

/// Pins the envelope layout and associated data: a fixed key, nonce and record ID must always
/// give these bytes. Not an external vector; it was produced by this code when the format was
/// set (format version 1), so a change here means existing vaults would stop opening.
@Test func theRecordEnvelopeFormatIsStable() throws {
    let key = SymmetricKey(data: Data(0..<32))
    let id = try #require(UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF"))
    let nonce = try AES.GCM.Nonce(data: Data(repeating: 0x24, count: 12))
    let sealed = try Envelope.seal(
        Data("fake record".utf8), key: key, purpose: .record, id: id, nonce: nonce)

    #expect(sealed == Vector.hex(Regression.recordEnvelope))
    #expect(try RecordSealer.open(sealed, recordID: id, key: key) == Data("fake record".utf8))
}

private enum Regression {
    static let recordEnvelope =
        "012424242424242424242424246090d2aac70dc763a86774fb873bb16c97524fee072811d6a472a3"
}
