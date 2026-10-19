import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for Recently Deleted (DESIGN.md §5). Every password and value is fake.
@MainActor
private func trashSession() async throws -> (VaultSession, InMemoryVaultStore, VaultGroup) {
    let store = InMemoryVaultStore()
    let session = try VaultSession(store: store)
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let group = try session.addGroup(
        VaultGroup(name: "Fake Logins", fields: [FieldTemplate(label: "Username"), FieldTemplate(label: "Note")]))
    return (session, store, group)
}

private let day: TimeInterval = 24 * 60 * 60

@MainActor
@Test func aTrashedEntryKeepsEverythingAndComesBack() async throws {
    let (session, store, group) = try await trashSession()
    let entry = try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Fake Shop", values: [group.fields[0].id: "fake.user"], notes: "fake notes",
            isFavorite: true))
    let ref = try session.addAttachment(
        to: entry.id, filename: "fake.txt", uti: "public.plain-text", contents: Data("fake".utf8))

    try session.moveEntryToTrash(id: entry.id)
    #expect(session.entries.isEmpty)
    #expect(session.favorites.isEmpty)
    #expect(session.search("Fake").isEmpty)
    #expect(session.search("Shop", inTrash: true).map(\.id) == [entry.id])
    #expect(store.attachments[ref.id] != nil)
    #expect(throws: VaultError.notFound) { try session.updateEntry(entry) }
    #expect(throws: VaultError.notFound) { try session.moveEntryToTrash(id: entry.id) }

    session.lock()
    #expect(session.deletedEntries.isEmpty)
    try await session.unlock(password: "fake-master")
    let trashed = try #require(session.deletedEntry(id: entry.id))
    #expect(trashed.deleted != nil)
    #expect(session.entries.isEmpty)

    try session.restoreEntry(id: entry.id)
    let restored = try #require(session.entry(id: entry.id))
    #expect(restored.deleted == nil)
    #expect(restored.values == entry.values && restored.notes == "fake notes" && restored.isFavorite)
    #expect(try session.attachmentContents(ref) == Data("fake".utf8))
    #expect(session.deletedEntries.isEmpty)
}

@MainActor
@Test func aTrashedGroupComesBackWithOnlyTheEntriesDeletedWithIt() async throws {
    let (session, _, group) = try await trashSession()
    let earlier = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Earlier"))
    let a = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake A"))
    let b = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake B"))
    try session.moveEntryToTrash(id: earlier.id)

    try session.moveGroupToTrash(id: group.id)
    #expect(session.groups.isEmpty && session.entries.isEmpty)
    #expect(session.deletedGroups.map(\.id) == [group.id])
    #expect(Set(session.deletedEntries.map(\.id)) == [earlier.id, a.id, b.id])

    // The deletion dates must survive sealing for the match to work.
    session.lock()
    try await session.unlock(password: "fake-master")
    try session.restoreGroup(id: group.id)
    #expect(session.groups.map(\.id) == [group.id])
    #expect(Set(session.entries.map(\.id)) == [a.id, b.id])
    #expect(session.deletedEntries.map(\.id) == [earlier.id])
}

@MainActor
@Test func restoringAnEntryBringsBackItsGroupButNotTheGroupsOtherEntries() async throws {
    let (session, _, group) = try await trashSession()
    let a = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake A"))
    let b = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake B"))
    try session.moveGroupToTrash(id: group.id)

    try session.restoreEntry(id: a.id)
    #expect(session.groups.map(\.id) == [group.id])
    #expect(session.entries.map(\.id) == [a.id])
    #expect(session.deletedEntries.map(\.id) == [b.id])
    #expect(session.deletedGroups.isEmpty)
}

@MainActor
@Test func anEntryWhoseGroupIsGoneCantBeRestored() async throws {
    let (session, store, group) = try await trashSession()
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Orphan"))
    try session.moveEntryToTrash(id: entry.id)
    // As if another device had deleted the group for good.
    try store.deleteRecords(ids: [group.id])
    try session.reload()

    #expect(throws: VaultError.unknownGroup) { try session.restoreEntry(id: entry.id) }
    #expect(session.deletedEntries.map(\.id) == [entry.id])
}

@MainActor
@Test func deletingForGoodRemovesRecordsAndAttachments() async throws {
    let (session, store, group) = try await trashSession()
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    let ref = try session.addAttachment(
        to: entry.id, filename: "fake.txt", uti: "public.plain-text", contents: Data("fake".utf8))
    let live = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Live"))

    #expect(throws: VaultError.notFound) { try session.deleteEntryPermanently(id: live.id) }
    #expect(throws: VaultError.notFound) { try session.deleteGroupPermanently(id: group.id) }

    try session.moveEntryToTrash(id: entry.id)
    try session.deleteEntryPermanently(id: entry.id)
    #expect(store.records[entry.id] == nil)
    #expect(store.attachments[ref.id] == nil)
    #expect(session.deletedEntries.isEmpty)
    #expect(session.entry(id: live.id) != nil)
}

@MainActor
@Test func emptyingTheTrashDeletesEverythingInIt() async throws {
    let (session, store, group) = try await trashSession()
    let other = try session.addGroup(VaultGroup(name: "Fake Other"))
    let a = try session.addEntry(VaultEntry(groupID: other.id, title: "Fake A"))
    let b = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake B"))
    let kept = try session.addEntry(VaultEntry(groupID: other.id, title: "Fake Kept"))
    try session.moveEntryToTrash(id: a.id)
    try session.moveGroupToTrash(id: group.id)

    try session.emptyTrash()
    #expect(session.deletedGroups.isEmpty && session.deletedEntries.isEmpty)
    #expect(store.records[a.id] == nil && store.records[b.id] == nil && store.records[group.id] == nil)
    #expect(session.entries.map(\.id) == [kept.id])
    #expect(session.groups.map(\.id) == [other.id])
}

@MainActor
@Test func itemsAreDeletedForGoodAfterThirtyDays() async throws {
    let (session, store, group) = try await trashSession()
    let other = try session.addGroup(VaultGroup(name: "Fake Other"))
    let loose = try session.addEntry(VaultEntry(groupID: other.id, title: "Fake Loose"))
    let inGroup = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake In Group"))
    try session.moveEntryToTrash(id: loose.id)
    try session.moveGroupToTrash(id: group.id)
    let deletedAt = try #require(session.deletedEntry(id: loose.id)?.deleted)

    #expect(try session.purgeExpiredItems(now: deletedAt.addingTimeInterval(29 * day)) == 0)
    #expect(session.deletedEntries.count == 2)

    #expect(try session.purgeExpiredItems(now: deletedAt.addingTimeInterval(30 * day + 60)) == 3)
    #expect(session.deletedEntries.isEmpty && session.deletedGroups.isEmpty)
    #expect(store.records[loose.id] == nil && store.records[inGroup.id] == nil && store.records[group.id] == nil)
    #expect(VaultSession.purgeDate(forDeletedAt: deletedAt) == deletedAt.addingTimeInterval(30 * day))
}

/// Saves `entry` as another device would, sealed under the vault key.
@MainActor
private func saveFromAnotherDevice(_ entry: VaultEntry, to store: InMemoryVaultStore, session: VaultSession) throws {
    let key = try #require(session.vaultKeyForBiometricUnlock())
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    try store.saveRecords([
        SealedRecord(
            id: entry.id, kind: .entry, modified: entry.modified, schemaVersion: VaultSession.recordSchemaVersion,
            ciphertext: RecordSealer.seal(encoder.encode(entry), recordID: entry.id, key: key))
    ])
}

@MainActor
@Test func unlockingDeletesExpiredItemsOnlyAfterTheyHaveBeenShownForAWeek() async throws {
    let (session, store, group) = try await trashSession()
    // An entry another device moved to Recently Deleted 31 days ago, seen here for the first time:
    // an old copy replayed through iCloud, or a device whose clock is far behind.
    let old = VaultEntry(groupID: group.id, title: "Fake Old", deleted: Date.now.addingTimeInterval(-31 * day))
    try saveFromAnotherDevice(old, to: store, session: session)

    session.lock()
    try await session.unlock(password: "fake-master")
    #expect(session.deletedEntries.map(\.id) == [old.id])
    #expect(store.records[old.id] != nil)
    #expect(try session.purgeExpiredItems(now: .now.addingTimeInterval(6 * day)) == 0)

    #expect(try session.purgeExpiredItems(now: .now.addingTimeInterval(7 * day + 60)) == 1)
    #expect(store.records[old.id] == nil)
}

@MainActor
@Test func aReloadAfterSyncNeverDeletesAnythingForGood() async throws {
    let (session, store, group) = try await trashSession()
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    try session.moveEntryToTrash(id: entry.id)
    // Long past both the retention and the notice, but only a reload happens.
    var expired = try #require(session.deletedEntry(id: entry.id))
    expired.deleted = Date.now.addingTimeInterval(-60 * day)
    try saveFromAnotherDevice(expired, to: store, session: session)

    try session.reload()
    #expect(session.deletedEntries.map(\.id) == [entry.id])
    #expect(store.records[entry.id] != nil)
}

@MainActor
@Test func aDeletionDateInTheFutureCountsFromWhenItWasSeen() async throws {
    let (session, store, group) = try await trashSession()
    let future = VaultEntry(groupID: group.id, title: "Fake Future", deleted: Date.now.addingTimeInterval(365 * day))
    try saveFromAnotherDevice(future, to: store, session: session)
    try session.reload()

    let shown = try #require(session.deletedEntry(id: future.id))
    let purgeDate = session.purgeDate(forTrashedItem: shown.id, deletedAt: try #require(shown.deleted))
    #expect(purgeDate < Date.now.addingTimeInterval(31 * day))
    #expect(try session.purgeExpiredItems(now: .now.addingTimeInterval(31 * day)) == 1)
}

@MainActor
@Test func whenAnItemWasFirstSeenSurvivesLockingButNotTheVault() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = InMemoryVaultStore()
    let session = try VaultSession(store: store, trashLedger: TrashLedger(directory: directory))
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let old = VaultEntry(groupID: group.id, title: "Fake Old", deleted: Date.now.addingTimeInterval(-31 * day))
    try saveFromAnotherDevice(old, to: store, session: session)
    try session.reload()
    let firstPurgeDate = session.purgeDate(forTrashedItem: old.id, deletedAt: try #require(old.deleted))

    // A later unlock, in a new session on the same files, keeps the first-seen date.
    session.lock()
    let reopened = try VaultSession(store: store, trashLedger: TrashLedger(directory: directory))
    try await reopened.unlock(password: "fake-master")
    #expect(reopened.purgeDate(forTrashedItem: old.id, deletedAt: try #require(old.deleted)) == firstPurgeDate)
    let sealed = try Data(contentsOf: directory.appendingPathComponent("TrashLedger.sealed"))
    #expect(!sealed.contains(Data(old.id.uuidString.utf8)))

    try reopened.deleteVault()
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("TrashLedger.sealed").path))
}

@MainActor
@Test func aTamperedTrashedEntryIsSkippedAndAWrongPasswordStillFails() async throws {
    let (session, store, group) = try await trashSession()
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    try session.moveEntryToTrash(id: entry.id)
    session.lock()

    await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: "fake-wrong") }

    var record = try #require(store.records[entry.id])
    record.ciphertext[record.ciphertext.count - 1] ^= 0x01
    try store.saveRecords([record])
    try await session.unlock(password: "fake-master")
    #expect(session.unreadableRecordCount == 1)
    #expect(session.deletedEntries.isEmpty)
    #expect(store.records[entry.id] != nil)
}

@MainActor
@Test func onlyTheTrashAPIMarksItemsDeleted() async throws {
    let (session, _, group) = try await trashSession()
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake", deleted: .now))
    #expect(entry.deleted == nil)
    var edited = entry
    edited.deleted = .now
    try session.updateEntry(edited)
    #expect(session.entry(id: entry.id)?.deleted == nil)

    session.lock()
    try await session.unlock(password: "fake-master")
    #expect(session.entries.map(\.id) == [entry.id])
}
