import CloudKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for the sync pieces that don't need iCloud: record mapping, conflict rules, the store
/// decorator and conflict copies. Every value is fake.
@MainActor
private func syncedSession() async throws -> (VaultSession, SyncedVaultStore, InMemoryVaultStore) {
    let base = InMemoryVaultStore()
    let synced = SyncedVaultStore(base: base)
    let session = try VaultSession(store: synced)
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    return (session, synced, base)
}

@Test func sealedRecordsRoundTripThroughCloudKitRecords() throws {
    let sealed = SealedRecord(
        id: UUID(), kind: .entry, modified: Date(timeIntervalSince1970: 1_000), schemaVersion: 1,
        ciphertext: Data([1, 2, 3, 4]))
    let record = SyncRecordMapping.record(for: sealed, systemFields: nil)

    #expect(record.recordType == "Entry")
    #expect(record.recordID.recordName == sealed.id.uuidString)
    #expect(record.recordID.zoneID.zoneName == "Vault")
    #expect(record.encryptedValues["payload"] as? Data == sealed.ciphertext)
    #expect(record["payload"] == nil)

    guard case .record(let back) = SyncRecordMapping.incoming(record) else {
        Issue.record("not a record")
        return
    }
    #expect(back == sealed)
}

@Test func metaRoundTripsThroughACloudKitRecord() throws {
    let meta = VaultMeta(
        formatVersion: 1, kdf: KDFParameters(salt: Data(0..<16), iterations: 3, memoryBytes: 64 << 20),
        wrappedVaultKey: Data([9, 9]), keyCheck: Data([8]), created: Date(timeIntervalSince1970: 1),
        modified: Date(timeIntervalSince1970: 2))
    let record = try SyncRecordMapping.record(for: meta, systemFields: nil)
    #expect(record.recordType == "VaultMeta" && record.recordID.recordName == "meta")
    guard case .meta(let back) = SyncRecordMapping.incoming(record) else {
        Issue.record("not meta")
        return
    }
    #expect(back == meta)
}

@Test func attachmentsTravelAsAssets() throws {
    let id = UUID()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
    try Data([7, 7, 7]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let record = SyncRecordMapping.attachmentRecord(id: id, fileURL: url, size: 3, systemFields: nil)
    #expect(record.recordType == "Attachment")
    guard case .attachment(let backID, let ciphertext) = SyncRecordMapping.incoming(record) else {
        Issue.record("not an attachment")
        return
    }
    #expect(backID == id && ciphertext == Data([7, 7, 7]))
}

@Test func systemFieldsAreKept() throws {
    let record = CKRecord(recordType: "Entry", recordID: SyncRecordMapping.recordID(for: .record(UUID())))
    let data = SyncRecordMapping.encodeSystemFields(record)
    let decoded = try #require(SyncRecordMapping.decodeSystemFields(data))
    #expect(decoded.recordID == record.recordID && decoded.recordType == "Entry")

    let sealed = SealedRecord(
        id: UUID(uuidString: record.recordID.recordName)!, kind: .entry, modified: .now, schemaVersion: 1,
        ciphertext: Data([1]))
    #expect(SyncRecordMapping.record(for: sealed, systemFields: data).recordID == record.recordID)
}

@Test func theLaterVersionWinsAndTiesGoToTheServer() {
    let earlier = Date(timeIntervalSince1970: 100)
    let later = Date(timeIntervalSince1970: 200)
    #expect(SyncRecordMapping.resolve(localModified: later, serverModified: earlier) == .keepLocal)
    #expect(SyncRecordMapping.resolve(localModified: earlier, serverModified: later) == .takeServer)
    #expect(SyncRecordMapping.resolve(localModified: later, serverModified: later) == .takeServer)
    #expect(SyncRecordMapping.resolve(localModified: earlier, serverModified: nil) == .keepLocal)
}

@Test func recordNamesMapBackToItems() {
    let id = UUID()
    #expect(SyncRecordMapping.item(for: SyncRecordMapping.recordID(for: .meta), isAttachment: false) == .meta)
    #expect(
        SyncRecordMapping.item(for: SyncRecordMapping.recordID(for: .record(id)), isAttachment: false) == .record(id))
    #expect(
        SyncRecordMapping.item(for: SyncRecordMapping.recordID(for: .attachment(id)), isAttachment: true)
            == .attachment(id))
}

@MainActor
@Test func localChangesAreQueuedButDirectWritesAreNot() async throws {
    let (session, synced, base) = try await syncedSession()
    var changes: [SyncChange] = []
    synced.onLocalChanges = { changes += $0 }

    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    let ref = try session.addAttachment(
        to: entry.id, filename: "f.txt", uti: "public.plain-text", contents: Data("x".utf8))
    try session.deleteEntry(id: entry.id)

    #expect(changes.contains(.save(.record(group.id))))
    #expect(changes.contains(.save(.record(entry.id))))
    #expect(changes.contains(.save(.attachment(ref.id))))
    #expect(changes.contains(.delete(.record(entry.id))))
    #expect(changes.contains(.delete(.attachment(ref.id))))

    changes = []
    try base.saveRecords([
        SealedRecord(id: UUID(), kind: .group, modified: .now, schemaVersion: 1, ciphertext: Data([1]))
    ])
    #expect(changes.isEmpty)
}

@MainActor
@Test func remoteRecordsAppearAfterReload() async throws {
    let (session, _, base) = try await syncedSession()
    let other = try VaultSession(store: base)
    try await other.unlock(password: "fake-master")
    try other.addGroup(VaultGroup(name: "Fake From Another Device"))

    try session.reload()
    #expect(session.groups.map(\.name) == ["Fake From Another Device"])
}

@MainActor
@Test func aLosingEntryIsKeptAsAConflictCopy() async throws {
    let (session, _, base) = try await syncedSession()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Example Bank", notes: "mine"))
    try session.addAttachment(to: entry.id, filename: "scan.png", uti: "public.png", contents: Data("x".utf8))
    let losing = try #require(base.records[entry.id])

    let copy = try #require(
        session.keepConflictCopy(of: losing, deviceName: "Fake Mac", at: Date(timeIntervalSince1970: 0)))
    #expect(copy.id != entry.id)
    #expect(copy.title.hasPrefix("Example Bank (conflict copy, Fake Mac, "))
    #expect(copy.attachments.isEmpty)
    #expect(copy.notes.contains("scan.png"))
    #expect(base.records[copy.id] != nil)
    #expect(session.entries.count == 2)

    session.lock()
    #expect(session.keepConflictCopy(of: losing, deviceName: "Fake Mac") == nil)
}

@MainActor
@Test func oversizedAttachmentsAreRefused() async throws {
    let (session, _, _) = try await syncedSession()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    #expect(throws: VaultError.attachmentTooLarge) {
        try session.addAttachment(
            to: entry.id, filename: "big.bin", uti: "public.data",
            contents: Data(count: VaultSession.maximumAttachmentSize + 1))
    }
}

@MainActor
@Test func backingStoresListEverythingToUpload() async throws {
    let (session, _, base) = try await syncedSession()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    let ref = try session.addAttachment(to: entry.id, filename: "a", uti: "public.data", contents: Data([1]))

    let items = Set(try base.allSyncItems())
    #expect(items == [.meta, .record(group.id), .record(entry.id), .attachment(ref.id)])
    #expect(try base.hasAttachment(id: ref.id))
    #expect(try !base.hasAttachment(id: entry.id))

    let disk = try SwiftDataVaultStore.inMemory()
    try disk.saveRecords([
        SealedRecord(id: entry.id, kind: .entry, modified: .now, schemaVersion: 1, ciphertext: Data([1]))
    ])
    try disk.setSystemFields(Data([5]), for: .record(entry.id))
    #expect(try disk.systemFields(for: .record(entry.id)) == Data([5]))
    #expect(try disk.allSyncItems() == [.record(entry.id)])
}
