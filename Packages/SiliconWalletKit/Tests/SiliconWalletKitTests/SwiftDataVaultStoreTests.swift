import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for the on-disk store. Every value is fake.
@MainActor
private enum Disk {
    static func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SiliconWalletTests-\(UUID().uuidString)", isDirectory: true)
    }

    static func meta() -> VaultMeta {
        VaultMeta(
            formatVersion: 1, kdf: KDFParameters(salt: Data(0..<16), iterations: 1, memoryBytes: 8 << 10),
            wrappedVaultKey: Data([1, 2, 3]),
            keyCheck: Data([4, 5]), created: Date(timeIntervalSince1970: 1_000),
            modified: Date(timeIntervalSince1970: 2_000))
    }

    static func record(_ kind: RecordKind = .entry, bytes: [UInt8] = [9, 9, 9]) -> SealedRecord {
        SealedRecord(
            id: UUID(), kind: kind, modified: Date(timeIntervalSince1970: 3_000), schemaVersion: 1,
            ciphertext: Data(bytes))
    }
}

@MainActor
@Test func metaRecordsAndAttachmentsSurviveReopening() throws {
    let directory = Disk.directory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let group = Disk.record(.group)
    let entry = Disk.record(.entry)
    let attachmentID = UUID()
    do {
        let store = try SwiftDataVaultStore(directory: directory)
        #expect(try store.loadMeta() == nil)
        try store.saveMeta(Disk.meta())
        try store.saveRecords([group, entry])
        try store.saveAttachment(id: attachmentID, ciphertext: Data([7, 7]))
    }

    let reopened = try SwiftDataVaultStore(directory: directory)
    #expect(try reopened.loadMeta() == Disk.meta())
    #expect(Set(try reopened.loadRecords().map(\.id)) == [group.id, entry.id])
    #expect(try reopened.loadRecords().first { $0.id == group.id } == group)
    #expect(try reopened.loadAttachment(id: attachmentID) == Data([7, 7]))
}

@MainActor
@Test func savingAnExistingRecordReplacesIt() throws {
    let store = try SwiftDataVaultStore.inMemory()
    var record = Disk.record()
    try store.saveRecords([record])
    record.ciphertext = Data([1])
    record.modified = Date(timeIntervalSince1970: 9_000)
    try store.saveRecords([record])

    #expect(try store.loadRecords() == [record])

    var meta = Disk.meta()
    try store.saveMeta(meta)
    meta.wrappedVaultKey = Data([8])
    try store.saveMeta(meta)
    #expect(try store.loadMeta() == meta)
}

@MainActor
@Test func recordsAndAttachmentsCanBeDeleted() throws {
    let store = try SwiftDataVaultStore.inMemory()
    let a = Disk.record()
    let b = Disk.record()
    try store.saveRecords([a, b])
    try store.deleteRecords(ids: [a.id])
    #expect(try store.loadRecords().map(\.id) == [b.id])

    let attachmentID = UUID()
    try store.saveAttachment(id: attachmentID, ciphertext: Data([1]))
    try store.deleteAttachments(ids: [attachmentID])
    #expect(try store.loadAttachment(id: attachmentID) == nil)
    #expect(!FileManager.default.fileExists(atPath: store.attachmentURL(attachmentID).path))
}

@MainActor
@Test func deleteAllEmptiesTheStore() throws {
    let store = try SwiftDataVaultStore.inMemory()
    try store.saveMeta(Disk.meta())
    try store.saveRecords([Disk.record()])
    let attachmentID = UUID()
    try store.saveAttachment(id: attachmentID, ciphertext: Data([1]))

    try store.deleteAll()
    #expect(try store.loadMeta() == nil)
    #expect(try store.loadRecords().isEmpty)
    #expect(try store.loadAttachment(id: attachmentID) == nil)
}

@MainActor
@Test func aVaultSessionWorksEndToEndOnDisk() async throws {
    let directory = Disk.directory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let entryID: UUID
    do {
        let session = try VaultSession(store: SwiftDataVaultStore(directory: directory))
        try await session.createVault(password: "fake-master", kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
        let logins = try #require(session.groups.first { $0.name == "Logins" })
        let entry = try session.addEntry(
            VaultEntry(
                groupID: logins.id, title: "Example Disk Bank", values: [logins.fields[1].id: "fake-disk-secret"],
                notes: "fake disk note"))
        try session.addAttachment(
            to: entry.id, filename: "fake-disk.txt", uti: "public.plain-text", contents: Data("fake disk file".utf8))
        entryID = entry.id
    }

    let session = try VaultSession(store: SwiftDataVaultStore(directory: directory))
    #expect(session.state == .locked)
    try await session.unlock(password: "fake-master")
    let entry = try #require(session.entry(id: entryID))
    #expect(entry.title == "Example Disk Bank")
    #expect(try session.attachmentContents(try #require(entry.attachments.first)) == Data("fake disk file".utf8))

    // Nothing readable anywhere in the store's files.
    var everything = Data()
    let files =
        FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
    for file in files where !file.hasDirectoryPath {
        everything.append((try? Data(contentsOf: file)) ?? Data())
    }
    #expect(!everything.isEmpty)
    for secret in [
        "Example Disk Bank", "fake-disk-secret", "fake disk note", "fake-disk.txt", "fake disk file", "Logins",
    ] {
        #expect(everything.range(of: Data(secret.utf8)) == nil, "\(secret) is on disk")
    }
}
