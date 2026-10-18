import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for `VaultSession` over the in-memory store. Every password and value is fake.
@MainActor
private enum Make {
    /// libsodium's minimum Argon2id cost, so the tests stay fast.
    static func fastKDF() -> KDFParameters { .generate(iterations: 1, memoryBytes: 8 << 10) }

    static func session(starterGroups: Bool = false) async throws -> (VaultSession, InMemoryVaultStore) {
        let store = InMemoryVaultStore()
        let session = try VaultSession(store: store)
        try await session.createVault(password: "fake-master", starterGroups: starterGroups, kdf: fastKDF())
        return (session, store)
    }

    static func loginsGroup() -> VaultGroup {
        VaultGroup(
            name: "Fake Logins",
            fields: [
                FieldTemplate(label: "Username"),
                FieldTemplate(label: "Password", kind: .password),
            ])
    }
}

@MainActor
@Test func aNewStoreHasNoVault() throws {
    let session = try VaultSession(store: InMemoryVaultStore())
    #expect(session.state == .noVault)
}

@MainActor
@Test func createLockAndUnlockRoundTrip() async throws {
    let (session, store) = try await Make.session()
    #expect(session.state == .unlocked)

    let group = try session.addGroup(Make.loginsGroup())
    let username = group.fields[0].id
    try session.addEntry(VaultEntry(groupID: group.id, title: "Example Bank", values: [username: "fake.user"]))

    session.lock()
    #expect(session.state == .locked)
    #expect(session.groups.isEmpty && session.entries.isEmpty)
    #expect(session.vaultKeyForBiometricUnlock() == nil)

    let reopened = try VaultSession(store: store)
    #expect(reopened.state == .locked)
    try await reopened.unlock(password: "fake-master")
    #expect(reopened.groups.map(\.name) == ["Fake Logins"])
    #expect(reopened.entries.first?.values[username] == "fake.user")
    #expect(reopened.unreadableRecordCount == 0)
}

@MainActor
@Test func aWrongPasswordDoesNotUnlock() async throws {
    let (session, _) = try await Make.session()
    session.lock()
    await #expect(throws: VaultError.wrongPassword) {
        try await session.unlock(password: "not-the-fake-master")
    }
    #expect(session.state == .locked)
    #expect(try await session.verifyPassword("fake-master"))
    #expect(try await !session.verifyPassword("nope"))
}

@MainActor
@Test func aVaultCantBeCreatedTwice() async throws {
    let (session, _) = try await Make.session()
    await #expect(throws: VaultError.vaultExists) {
        try await session.createVault(password: "x", kdf: Make.fastKDF())
    }
}

@MainActor
@Test func starterGroupsAreCreatedAndSealed() async throws {
    let (session, store) = try await Make.session(starterGroups: true)
    #expect(
        session.groups.map(\.name) == ["Logins", "Credit Cards", "Bank Accounts", "Software Licences", "Secure Notes"])
    #expect(store.records.count == 5)
}

@MainActor
@Test func theStoreNeverHoldsPlaintext() async throws {
    let (session, store) = try await Make.session()
    let group = try session.addGroup(Make.loginsGroup())
    let password = group.fields[1].id
    let entry = try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Example Bank", values: [password: "fake-secret-1234"],
            notes: "fake note text"))
    try session.addAttachment(
        to: entry.id, filename: "fake-scan.png", uti: "public.png", contents: Data("fake image bytes".utf8))

    var everything = Data()
    for record in store.records.values { everything.append(record.ciphertext) }
    for attachment in store.attachments.values { everything.append(attachment) }
    everything.append(try JSONEncoder().encode(store.meta))

    for secret in [
        "Example Bank", "fake-secret-1234", "fake note text", "Fake Logins", "Password", "fake-scan.png",
        "fake image bytes",
    ] {
        #expect(everything.range(of: Data(secret.utf8)) == nil, "\(secret) is in the store")
    }
}

@MainActor
@Test func groupsCanBeUpdatedReorderedAndDeleted() async throws {
    let (session, store) = try await Make.session()
    let a = try session.addGroup(VaultGroup(name: "Fake A"))
    let b = try session.addGroup(VaultGroup(name: "Fake B"))
    #expect(session.groups.map(\.name) == ["Fake A", "Fake B"])

    var renamed = a
    renamed.name = "Fake A2"
    renamed.fields.append(FieldTemplate(label: "PIN", kind: .number, isConcealed: true))
    try session.updateGroup(renamed)
    #expect(session.group(id: a.id)?.name == "Fake A2")

    try session.reorderGroups([b.id, a.id])
    #expect(session.groups.map(\.id) == [b.id, a.id])

    try session.deleteGroup(id: b.id)
    #expect(session.groups.map(\.id) == [a.id])
    #expect(store.records[b.id] == nil)
}

@MainActor
@Test func deletingAGroupDeletesItsEntriesAndAttachments() async throws {
    let (session, store) = try await Make.session()
    let doomed = try session.addGroup(VaultGroup(name: "Fake Doomed"))
    let kept = try session.addGroup(VaultGroup(name: "Fake Kept"))
    let e1 = try session.addEntry(VaultEntry(groupID: doomed.id, title: "Fake 1"))
    try session.addEntry(VaultEntry(groupID: kept.id, title: "Fake 2"))
    let ref = try session.addAttachment(
        to: e1.id, filename: "a.txt", uti: "public.plain-text", contents: Data("x".utf8))

    try session.deleteGroup(id: doomed.id)
    #expect(session.entries.map(\.title) == ["Fake 2"])
    #expect(store.records[e1.id] == nil)
    #expect(store.attachments[ref.id] == nil)
}

@MainActor
@Test func entriesCanBeAddedUpdatedFavouritedAndDeleted() async throws {
    let (session, store) = try await Make.session()
    let group = try session.addGroup(Make.loginsGroup())
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake Shop"))

    var edited = entry
    edited.title = "Fake Shop 2"
    edited.extraFields = [CustomField(label: "Member No", value: "FAKE-1")]
    try session.updateEntry(edited)
    try session.setFavorite(true, entryID: entry.id)

    #expect(session.entry(id: entry.id)?.title == "Fake Shop 2")
    #expect(session.favorites.map(\.id) == [entry.id])
    #expect(try #require(session.entry(id: entry.id)).modified >= entry.modified)

    try session.deleteEntry(id: entry.id)
    #expect(session.entries.isEmpty)
    #expect(store.records[entry.id] == nil)
}

@MainActor
@Test func anEntryNeedsAnExistingGroup() async throws {
    let (session, _) = try await Make.session()
    #expect(throws: VaultError.unknownGroup) {
        try session.addEntry(VaultEntry(groupID: UUID(), title: "Fake"))
    }
}

@MainActor
@Test func editsAreRefusedWhileLocked() async throws {
    let (session, _) = try await Make.session()
    session.lock()
    #expect(throws: VaultError.locked) {
        try session.addGroup(VaultGroup(name: "Fake"))
    }
}

@MainActor
@Test func searchMatchesVisibleTextButNeverConcealedValues() async throws {
    let (session, _) = try await Make.session()
    let group = try session.addGroup(Make.loginsGroup())
    let username = group.fields[0].id
    let password = group.fields[1].id
    try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Café Example", values: [username: "fake.user", password: "hunter-fake"],
            notes: "renewal in March"))
    try session.addEntry(VaultEntry(groupID: group.id, title: "Other Example"))

    #expect(session.search("cafe").map(\.title) == ["Café Example"])
    #expect(session.search("FAKE.USER").map(\.title) == ["Café Example"])
    #expect(session.search("march").map(\.title) == ["Café Example"])
    #expect(session.search("username").map(\.title) == ["Café Example"])
    #expect(session.search("example renewal").map(\.title) == ["Café Example"])
    #expect(session.search("hunter").isEmpty)
    #expect(session.search("  ").count == 2)
}

@MainActor
@Test func changingThePasswordKeepsTheData() async throws {
    let (session, store) = try await Make.session()
    try session.addGroup(VaultGroup(name: "Fake Kept"))
    await #expect(throws: VaultError.wrongPassword) {
        try await session.changePassword(current: "wrong", new: "fake-new", kdf: Make.fastKDF())
    }
    try await session.changePassword(current: "fake-master", new: "fake-new", kdf: Make.fastKDF())

    let reopened = try VaultSession(store: store)
    await #expect(throws: VaultError.wrongPassword) {
        try await reopened.unlock(password: "fake-master")
    }
    try await reopened.unlock(password: "fake-new")
    #expect(reopened.groups.map(\.name) == ["Fake Kept"])
}

@MainActor
@Test func theVaultKeyUnlocksOnlyItsOwnVault() async throws {
    let (session, store) = try await Make.session()
    try session.addGroup(VaultGroup(name: "Fake"))
    let key = try #require(session.vaultKeyForBiometricUnlock())
    session.lock()

    #expect(throws: VaultError.wrongPassword) {
        try session.unlock(vaultKey: VaultKey.generate())
    }
    try session.unlock(vaultKey: key)
    #expect(session.groups.count == 1)
    _ = store
}

@MainActor
@Test func attachmentsRoundTripAndAreRemoved() async throws {
    let (session, store) = try await Make.session()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    let entry = try session.addEntry(VaultEntry(groupID: group.id, title: "Fake"))
    let contents = Data((0..<5000).map { UInt8($0 % 251) })

    let ref = try session.addAttachment(to: entry.id, filename: "fake.bin", uti: "public.data", contents: contents)
    #expect(try session.attachmentContents(ref) == contents)
    #expect(session.entry(id: entry.id)?.attachments == [ref])

    try session.removeAttachment(id: ref.id, from: entry.id)
    #expect(store.attachments[ref.id] == nil)
    #expect(throws: VaultError.attachmentUnavailable) {
        try session.attachmentContents(ref)
    }
}

@MainActor
@Test func aTamperedRecordIsSkippedAndCounted() async throws {
    let (session, store) = try await Make.session()
    let good = try session.addGroup(VaultGroup(name: "Fake Good"))
    let bad = try session.addGroup(VaultGroup(name: "Fake Bad"))
    session.lock()

    var record = try #require(store.records[bad.id])
    record.ciphertext[record.ciphertext.count - 1] ^= 1
    try store.saveRecords([record])

    try await session.unlock(password: "fake-master")
    #expect(session.groups.map(\.id) == [good.id])
    #expect(session.unreadableRecordCount == 1)
}

@MainActor
@Test func aRecordMovedToAnotherIDIsRejected() async throws {
    let (session, store) = try await Make.session()
    let group = try session.addGroup(VaultGroup(name: "Fake"))
    session.lock()

    var moved = try #require(store.records[group.id])
    moved.id = UUID()
    try store.saveRecords([moved])

    try await session.unlock(password: "fake-master")
    #expect(session.groups.count == 1)
    #expect(session.unreadableRecordCount == 1)
}

@MainActor
@Test func reloadPicksUpRecordsWrittenByAnotherSession() async throws {
    let (session, store) = try await Make.session()
    let other = try VaultSession(store: store)
    try await other.unlock(password: "fake-master")
    try other.addGroup(VaultGroup(name: "Fake From Elsewhere"))

    #expect(session.groups.isEmpty)
    try session.reload()
    #expect(session.groups.map(\.name) == ["Fake From Elsewhere"])
}

@MainActor
@Test func deletingTheVaultClearsTheStore() async throws {
    let (session, store) = try await Make.session(starterGroups: true)
    try session.deleteVault()
    #expect(session.state == .noVault)
    #expect(store.meta == nil && store.records.isEmpty)
}
