import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Tampering cases the vault must refuse with the right error (DESIGN.md §5). Every password and
/// value is fake.
@MainActor
private func tamperSession() async throws -> (VaultSession, InMemoryVaultStore) {
    let store = InMemoryVaultStore()
    let session = try VaultSession(store: store)
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    return (session, store)
}

@MainActor
@Test func aTamperedAttachmentIsReportedCorrupt() async throws {
    let (session, store) = try await tamperSession()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Scan"))
    let ref = try session.addAttachment(
        to: entry.id, filename: "fake.txt", uti: "public.plain-text", contents: Data("fake contents".utf8))
    #expect(try session.attachmentContents(ref) == Data("fake contents".utf8))

    var sealed = try #require(store.attachments[ref.id])
    sealed[sealed.count - 1] ^= 0x01
    try store.saveAttachment(id: ref.id, ciphertext: sealed)
    #expect(throws: VaultError.attachmentCorrupt) { try session.attachmentContents(ref) }

    // Intact bytes, but a digest that doesn't match them.
    try store.saveAttachment(
        id: ref.id,
        ciphertext: AttachmentSealer.seal(Data("other contents".utf8), attachmentID: ref.id, fileKey: ref.symmetricKey))
    #expect(throws: VaultError.attachmentCorrupt) { try session.attachmentContents(ref) }

    // Another attachment's sealed file under this one's ID.
    let other = try session.addAttachment(
        to: entry.id, filename: "other.txt", uti: "public.plain-text", contents: Data("fake other".utf8))
    try store.saveAttachment(id: ref.id, ciphertext: try #require(store.attachments[other.id]))
    #expect(throws: VaultError.attachmentCorrupt) { try session.attachmentContents(ref) }
}

@MainActor
@Test func aTamperedKeyCheckRefusesTheBiometricKey() async throws {
    let (session, store) = try await tamperSession()
    let key = try #require(session.vaultKeyForBiometricUnlock())
    session.lock()

    var meta = try #require(store.meta)
    meta.keyCheck[meta.keyCheck.count - 1] ^= 0x01
    try store.saveMeta(meta)
    #expect(throws: VaultError.wrongPassword) { try session.unlock(vaultKey: key) }
    #expect(!session.isUnlocked)
}

@MainActor
@Test func aWrongBiometricKeyIsRefused() async throws {
    let (session, _) = try await tamperSession()
    session.lock()
    #expect(throws: VaultError.wrongPassword) { try session.unlock(vaultKey: VaultKey.generate()) }
}

@MainActor
@Test func aTamperedWrappedVaultKeyRefusesThePassword() async throws {
    let (session, store) = try await tamperSession()
    session.lock()

    var meta = try #require(store.meta)
    meta.wrappedVaultKey[meta.wrappedVaultKey.count / 2] ^= 0x01
    try store.saveMeta(meta)
    await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: "fake-master") }
    #expect(!session.isUnlocked)
}

@MainActor
@Test func aNewerVaultFormatIsRefused() async throws {
    let (session, store) = try await tamperSession()
    session.lock()

    var meta = try #require(store.meta)
    meta.formatVersion = SiliconWalletKit.formatVersion + 1
    try store.saveMeta(meta)
    await #expect(throws: VaultError.unsupportedFormat(SiliconWalletKit.formatVersion + 1)) {
        try await session.unlock(password: "fake-master")
    }
}

@MainActor
@Test func aRecordWithANewerSchemaIsLeftAloneAndCounted() async throws {
    let (session, store) = try await tamperSession()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Future"))
    var record = try #require(store.records[entry.id])
    record.schemaVersion = VaultSession.recordSchemaVersion + 1
    try store.saveRecords([record])

    session.lock()
    try await session.unlock(password: "fake-master")
    #expect(session.entry(id: entry.id) == nil)
    #expect(session.unreadableRecordCount == 1)
    #expect(store.records[entry.id] == record)
}

@MainActor
@Test func aTamperedOrForeignAccessLogReadsAsEmpty() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TamperTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = VaultKey.generate()
    let log = AccessLog(directory: directory)
    log.record(AccessEvent(kind: .unlockedWithPassword), key: key)
    let url = directory.appendingPathComponent("AccessLog.sealed")

    var sealed = try Data(contentsOf: url)
    sealed[sealed.count - 1] ^= 0x01
    try sealed.write(to: url)
    #expect(log.load(key: key).isEmpty)

    // Another vault's log, swapped in.
    let otherKey = VaultKey.generate()
    AccessLog(directory: directory).record(AccessEvent(kind: .exported), key: otherKey)
    #expect(log.load(key: key).isEmpty)
    // A log can't be opened as a record either.
    #expect(throws: CryptoError.authenticationFailed) {
        try RecordSealer.open(try Data(contentsOf: url), recordID: UUID(), key: otherKey)
    }
}
