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

@MainActor
@Test func unlockingDeletesExpiredItems() async throws {
    let (session, store, group) = try await trashSession()
    let key = try #require(session.vaultKeyForBiometricUnlock())
    // An entry another device moved to Recently Deleted 31 days ago.
    let old = VaultEntry(groupID: group.id, title: "Fake Old", deleted: Date.now.addingTimeInterval(-31 * day))
    let recent = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Recent"))
    try session.moveEntryToTrash(id: recent.id)
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    try store.saveRecords([
        SealedRecord(
            id: old.id, kind: .entry, modified: .now, schemaVersion: VaultSession.recordSchemaVersion,
            ciphertext: RecordSealer.seal(encoder.encode(old), recordID: old.id, key: key))
    ])

    session.lock()
    try await session.unlock(password: "fake-master")
    #expect(session.deletedEntries.map(\.id) == [recent.id])
    #expect(store.records[old.id] == nil)
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
