import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for export and import (ADR-0008). Every password and value is fake.
private let fastKDF = KDFParameters.generate(iterations: 1, memoryBytes: 8 << 10)

@MainActor
private func exportingSession() async throws -> (VaultSession, VaultGroup, VaultEntry, AttachmentRef) {
    let session = try VaultSession(store: InMemoryVaultStore())
    try await session.createVault(password: "fake-master", starterGroups: false, kdf: fastKDF)
    let group = try session.addGroup(
        VaultGroup(
            name: "Fake Cards", icon: "creditcard",
            fields: [FieldTemplate(label: "Number"), FieldTemplate(label: "PIN", kind: .number, isConcealed: true)]))
    let entry = try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Fake Card",
            values: [group.fields[0].id: "0000 0000", group.fields[1].id: "0000"],
            extraFields: [CustomField(label: "Fake Member", isMonospaced: true, value: "FAKE-1")], notes: "fake notes",
            isFavorite: true))
    let ref = try session.addAttachment(
        to: entry.id, filename: "fake.txt", uti: "public.plain-text", contents: Data("fake attachment".utf8))
    return (session, group, try #require(session.entry(id: entry.id)), ref)
}

@MainActor
private func emptySession() async throws -> VaultSession {
    let session = try VaultSession(store: InMemoryVaultStore())
    try await session.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    return session
}

@MainActor
private func expectSameContent(_ imported: VaultEntry, _ original: VaultEntry) {
    #expect(imported.title == original.title)
    #expect(imported.values == original.values)
    #expect(imported.extraFields == original.extraFields)
    #expect(imported.notes == original.notes && imported.isFavorite == original.isFavorite)
    #expect(abs(imported.created.timeIntervalSince(original.created)) < 1)
    #expect(abs(imported.modified.timeIntervalSince(original.modified)) < 1)
}

// MARK: - Round trips

@MainActor
@Test func aBackupRoundTripsEverything() async throws {
    let (source, group, entry, ref) = try await exportingSession()
    let backup = try await source.exportBackup(password: "fake-export", kdf: fastKDF)
    #expect(ExportFile.kind(of: backup) == .backup)

    let target = try await emptySession()
    let plan = try ExportFile.plan(backup: backup, password: "fake-export")
    let summary = try target.importItems(plan)
    #expect(summary.groups == 1 && summary.entries == 1 && summary.attachments == 1)

    let importedGroup = try #require(target.group(id: group.id))
    #expect(
        importedGroup.name == group.name && importedGroup.icon == group.icon && importedGroup.fields == group.fields)
    let imported = try #require(target.entry(id: entry.id))
    expectSameContent(imported, entry)
    let importedRef = try #require(imported.attachments.first)
    #expect(importedRef.filename == ref.filename && importedRef.uti == ref.uti)
    #expect(importedRef.fileKey != ref.fileKey)
    #expect(try target.attachmentContents(importedRef) == Data("fake attachment".utf8))
}

@MainActor
@Test func jsonRoundTripsEverythingAndIsReadable() async throws {
    let (source, _, entry, _) = try await exportingSession()
    let json = try source.exportJSON()
    #expect(ExportFile.kind(of: json) == .json)
    let text = try #require(String(data: json, encoding: .utf8))
    #expect(text.contains("\"silicon-wallet-export\""))
    #expect(text.contains("Fake Card") && text.contains("FAKE-1"))
    #expect(text.contains(Data("fake attachment".utf8).base64EncodedString()))

    let target = try await emptySession()
    let summary = try target.importItems(try ExportFile.plan(json: json))
    #expect(summary.entries == 1 && summary.attachments == 1)
    let imported = try #require(target.entry(id: entry.id))
    expectSameContent(imported, entry)
    #expect(try target.attachmentContents(try #require(imported.attachments.first)) == Data("fake attachment".utf8))
}

@MainActor
@Test func noFileKeyOrDeletedItemIsExported() async throws {
    let (source, group, _, ref) = try await exportingSession()
    let gone = try source.addEntry(VaultEntry(groupID: group.id, title: "Fake Deleted"))
    try source.moveEntryToTrash(id: gone.id)
    let text = try #require(String(data: try source.exportJSON(), encoding: .utf8))
    #expect(!text.contains("fileKey"))
    #expect(!text.contains(ref.fileKey.base64EncodedString()))
    #expect(!text.contains("Fake Deleted"))
}

@MainActor
@Test func aBackupHidesEverythingButItsKDFParameters() async throws {
    let (source, _, _, _) = try await exportingSession()
    let backup = try await source.exportBackup(password: "fake-export", kdf: fastKDF)
    for secret in ["Fake Card", "fake notes", "FAKE-1", "fake attachment", "Fake Cards", "fake.txt"] {
        #expect(backup.range(of: Data(secret.utf8)) == nil)
    }
}

// MARK: - Importing into a vault that has some of it

@MainActor
@Test func importingTheSameFileTwiceAddsNothing() async throws {
    let (source, _, _, _) = try await exportingSession()
    let json = try source.exportJSON()
    let target = try await emptySession()
    try target.importItems(try ExportFile.plan(json: json))
    let again = try target.importItems(try ExportFile.plan(json: json))
    #expect(again.groups == 0 && again.entries == 0 && again.attachments == 0)
    #expect(again.groupsAlreadyHere == 1 && again.entriesAlreadyHere == 1)
    #expect(target.entries.count == 1 && target.groups.count == 1)

    // Back into the vault it came from: everything is already there.
    let home = try source.importPreview(try ExportFile.plan(json: json))
    #expect(home.entries == 0 && home.entriesAlreadyHere == 1)
}

@MainActor
@Test func anEntryInRecentlyDeletedIsNotImportedAgain() async throws {
    let (source, _, entry, _) = try await exportingSession()
    let json = try source.exportJSON()
    try source.moveEntryToTrash(id: entry.id)
    let summary = try source.importItems(try ExportFile.plan(json: json))
    #expect(summary.entries == 0 && summary.entriesAlreadyHere == 1)
    #expect(source.entry(id: entry.id) == nil)
}

@MainActor
@Test func aNewEntryForADeletedGroupBringsTheGroupBackAlone() async throws {
    let (source, group, entry, _) = try await exportingSession()
    let json = try source.exportJSON()
    let other = try source.addEntry(VaultEntry(groupID: group.id, title: "Fake Other"))
    try source.moveGroupToTrash(id: group.id)
    try source.deleteEntryPermanently(id: entry.id)

    let summary = try source.importItems(try ExportFile.plan(json: json))
    #expect(summary.restoredGroups == 1 && summary.entries == 1 && summary.groups == 0)
    #expect(source.group(id: group.id) != nil)
    #expect(source.entry(id: entry.id)?.groupID == group.id)
    // The group comes back alone; the entry deleted with it stays in Recently Deleted.
    #expect(source.entry(id: other.id) == nil && source.deletedEntry(id: other.id) != nil)
}

@MainActor
@Test func valuesForFieldsTheGroupNoLongerHasBecomeExtraFields() async throws {
    let (source, group, entry, _) = try await exportingSession()
    let json = try source.exportJSON()
    try source.moveEntryToTrash(id: entry.id)
    try source.deleteEntryPermanently(id: entry.id)
    var edited = try #require(source.group(id: group.id))
    edited.fields.removeAll { $0.label == "PIN" }
    try source.updateGroup(edited)

    try source.importItems(try ExportFile.plan(json: json))
    let imported = try #require(source.entry(id: entry.id))
    #expect(imported.values == [group.fields[0].id: "0000 0000"])
    let pin = try #require(imported.extraFields.first { $0.label == "PIN" })
    #expect(pin.value == "0000" && pin.isConcealed && pin.kind == .number)
}

@MainActor
@Test func theImportIsLoggedAndSurvivesALock() async throws {
    let (source, _, _, _) = try await exportingSession()
    let backup = try await source.exportBackup(password: "fake-export", kdf: fastKDF)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = try VaultSession(store: InMemoryVaultStore(), accessLog: AccessLog(directory: directory))
    try await target.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    try target.importItems(try ExportFile.plan(backup: backup, password: "fake-export"))
    #expect(target.accessEvents().contains { $0.kind == .importedFromFile })
    target.lock()
    try await target.unlock(password: "fake-other")
    #expect(target.entries.count == 1 && target.unreadableRecordCount == 0)
}

// MARK: - Wrong passwords and hostile files

@MainActor
@Test func aWrongExportPasswordIsRefused() async throws {
    let (source, _, _, _) = try await exportingSession()
    let backup = try await source.exportBackup(password: "fake-export", kdf: fastKDF)
    #expect(throws: ExportFileError.wrongPasswordOrDamaged) {
        try ExportFile.plan(backup: backup, password: "fake-master")
    }
}

@MainActor
private func fakeBackup() async throws -> Data {
    let (source, _, _, _) = try await exportingSession()
    return try await source.exportBackup(password: "fake-export", kdf: fastKDF)
}

/// Where the parts of a backup start: (manifest, first attachment chunk).
private func offsets(_ backup: Data) -> (manifest: Int, attachment: Int) {
    func integer(_ at: Int, _ count: Int) -> Int {
        backup[backup.startIndex + at..<backup.startIndex + at + count].reduce(0) { $0 << 8 | Int($1) }
    }
    let headerLength = integer(10, 4)
    let manifestLengthAt = 14 + headerLength
    let manifest = manifestLengthAt + 8
    return (manifest, manifest + integer(manifestLengthAt, 8))
}

@MainActor
@Test func aTamperedManifestIsRefused() async throws {
    var backup = try await fakeBackup()
    backup[offsets(backup).manifest + 20] ^= 0x01
    #expect(throws: ExportFileError.wrongPasswordOrDamaged) {
        try ExportFile.plan(backup: backup, password: "fake-export")
    }
}

@MainActor
@Test func aTamperedAttachmentIsRefused() async throws {
    var backup = try await fakeBackup()
    backup[backup.count - 5] ^= 0x01
    #expect(throws: ExportFileError.damaged) { try ExportFile.plan(backup: backup, password: "fake-export") }
}

@MainActor
@Test func anAttachmentChunkUnderAnotherIDIsRefused() async throws {
    var backup = try await fakeBackup()
    backup[offsets(backup).attachment] ^= 0x01
    #expect(throws: ExportFileError.damaged) { try ExportFile.plan(backup: backup, password: "fake-export") }
}

@MainActor
@Test func aTruncatedOrExtendedBackupIsRefused() async throws {
    let backup = try await fakeBackup()
    for cut in [backup.count - 1, offsets(backup).attachment, offsets(backup).manifest + 3, 12] {
        #expect(throws: ExportFileError.self) {
            try ExportFile.plan(backup: backup.prefix(cut), password: "fake-export")
        }
    }
    #expect(throws: ExportFileError.damaged) {
        try ExportFile.plan(backup: backup + Data(count: 30), password: "fake-export")
    }
}

@MainActor
@Test func aBackupWithParametersOutOfLimitsIsRefusedBeforeDerivingAKey() async throws {
    let header = try JSONEncoder().encode(
        ["kdf": KDFParameters(salt: Data(count: 16), iterations: 1_000, memoryBytes: 1 << 40)])
    var backup = ExportFile.magic + Data([0, 1])
    backup += withUnsafeBytes(of: UInt32(header.count).bigEndian) { Data($0) } + header
    backup += withUnsafeBytes(of: UInt64(0).bigEndian) { Data($0) }
    #expect(throws: ExportFileError.damaged) { try ExportFile.plan(backup: backup, password: "fake-export") }
}

@MainActor
@Test func otherFilesAndNewerFormatsAreRefused() async throws {
    var backup = try await fakeBackup()
    backup[9] = 2
    #expect(throws: ExportFileError.unsupportedVersion) { try ExportFile.plan(backup: backup, password: "fake-export") }
    #expect(throws: ExportFileError.notAnExport) {
        try ExportFile.plan(backup: Data("SQLite format 3".utf8), password: "fake-export")
    }
    #expect(ExportFile.kind(of: Data("SQLite format 3".utf8)) == nil)
    #expect(throws: ExportFileError.notAnExport) { try ExportFile.plan(json: Data(#"{"items": []}"#.utf8)) }
    #expect(throws: ExportFileError.unsupportedVersion) {
        try ExportFile.plan(json: Data(#"{"format": "silicon-wallet-export", "version": 2}"#.utf8))
    }
    #expect(throws: ExportFileError.damaged) {
        try ExportFile.plan(json: Data(#"{"format": "silicon-wallet-export", "version": 1, "groups": 3}"#.utf8))
    }
}

@MainActor
@Test func aJSONAttachmentThatDoesntMatchItsHashIsRefused() async throws {
    let (source, _, _, _) = try await exportingSession()
    let json = try source.exportJSON()
    let text = try #require(String(data: json, encoding: .utf8)).replacingOccurrences(
        of: Data("fake attachment".utf8).base64EncodedString(), with: Data("fake changed!!!".utf8).base64EncodedString()
    )
    #expect(throws: ExportFileError.damaged) { try ExportFile.plan(json: Data(text.utf8)) }
}

@Test func repeatedIDsKeepTheirFirstUseAndOversizedAttachmentsAreLeftOut() throws {
    let groupID = UUID()
    let entryID = UUID()
    let attachment = ExportAttachment(
        id: UUID(), filename: "fake.bin", type: "public.data", size: 4, sha256: nil, data: Data(count: 4))
    let entry = ExportEntry(
        id: entryID, groupID: groupID, title: "Fake First", values: ["not-a-uuid": "fake loose value"], extraFields: [],
        notes: "", favourite: false, created: .now, modified: .now, attachments: [attachment])
    var second = entry
    second.title = "Fake Second"
    let group = ExportGroup(id: groupID, name: "", icon: "", order: 0, modified: .now, fields: [])
    let document = ExportDocument(exported: .now, groups: [group, group], entries: [entry, second])

    let plan = try ExportFile.plan(document, maximumAttachmentSize: 3) { $0.data }
    #expect(plan.groups.count == 1 && plan.groups[0].name == "Imported" && plan.groups[0].icon == "folder")
    #expect(plan.entries.map(\.title) == ["Fake First"])
    #expect(plan.entries[0].extraFields.map(\.value) == ["fake loose value"])
    #expect(plan.attachments.isEmpty && plan.leftOutAttachmentCount == 1)
}
