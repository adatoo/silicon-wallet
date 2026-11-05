import Foundation
import Testing

@testable import SiliconWalletKit

@Test func movingAnEntryKeepsEveryValue() {
    let old = VaultGroup(
        name: "Fake Old",
        fields: [
            FieldTemplate(label: "Username"),
            FieldTemplate(label: "Password", kind: .password),
            FieldTemplate(label: "Member Number"),
            FieldTemplate(label: "Empty"),
        ])
    let new = VaultGroup(
        name: "Fake New",
        fields: [
            FieldTemplate(label: "password", kind: .password),
            FieldTemplate(label: "Website", kind: .url),
            FieldTemplate(label: "Support Phone", kind: .phone),
        ])
    let entry = VaultEntry(
        groupID: old.id, title: "Fake",
        values: [old.fields[0].id: "fake.user", old.fields[1].id: "fake-pass", old.fields[2].id: "FAKE-1"],
        extraFields: [CustomField(label: "Support Phone", kind: .phone, value: "+44 20 0000 0000")])

    let moved = entry.moved(from: old, to: new)

    #expect(moved.groupID == new.id)
    #expect(moved.values == [new.fields[0].id: "fake-pass", new.fields[2].id: "+44 20 0000 0000"])
    #expect(moved.extraFields.map(\.label) == ["Username", "Member Number"])
    #expect(moved.extraFields.map(\.value) == ["fake.user", "FAKE-1"])
    #expect(moved.title == entry.title && moved.id == entry.id)
}

@Test func movingConcealedValuesKeepsThemConcealed() {
    let old = VaultGroup(name: "Fake Old", fields: [FieldTemplate(label: "PIN", kind: .number, isConcealed: true)])
    let new = VaultGroup(name: "Fake New")
    let entry = VaultEntry(groupID: old.id, title: "Fake", values: [old.fields[0].id: "0000"])

    let moved = entry.moved(from: old, to: new)
    #expect(moved.extraFields.first?.isConcealed == true)
    #expect(moved.extraFields.first?.kind == .number)
}

@Test func movingKeepsTheMonospacedChoice() {
    let old = VaultGroup(name: "Fake Old", fields: [FieldTemplate(label: "Licence Key", isMonospaced: true)])
    let new = VaultGroup(name: "Fake New")
    let entry = VaultEntry(groupID: old.id, title: "Fake", values: [old.fields[0].id: "FAKE-KEY"])

    #expect(entry.moved(from: old, to: new).extraFields.first?.isMonospaced == true)
}

@Test func movingWithinTheSameGroupChangesNothing() {
    let group = VaultGroup(name: "Fake", fields: [FieldTemplate(label: "A")])
    let entry = VaultEntry(groupID: group.id, title: "Fake", values: [group.fields[0].id: "x"])
    #expect(entry.moved(from: group, to: group) == entry)
}

// MARK: - VaultSession.moveEntry

@MainActor
private func movingSession() async throws -> (VaultSession, VaultGroup, VaultGroup) {
    let session = try VaultSession(store: InMemoryVaultStore())
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let old = try session.addGroup(
        VaultGroup(name: "Fake Custom Cards", fields: [FieldTemplate(label: "Number"), FieldTemplate(label: "Bank")]))
    let new = try session.addGroup(
        VaultGroup(name: "Fake Cards", fields: [FieldTemplate(label: "number"), FieldTemplate(label: "PIN")]))
    return (session, old, new)
}

@MainActor
@Test func theSessionMovesAnEntryKeepingEveryValue() async throws {
    let (session, old, new) = try await movingSession()
    let entry = try session.addEntry(
        VaultEntry(
            groupID: old.id, title: "Fake Card", values: [old.fields[0].id: "0000", old.fields[1].id: "Fake Bank"],
            extraFields: [CustomField(label: "PIN", value: "1111")], notes: "fake notes", isFavorite: true))

    try session.moveEntry(id: entry.id, toGroup: new.id)

    let moved = try #require(session.entry(id: entry.id))
    #expect(moved.groupID == new.id)
    #expect(moved.values == [new.fields[0].id: "0000", new.fields[1].id: "1111"])
    #expect(moved.extraFields.map(\.label) == ["Bank"])
    #expect(moved.notes == "fake notes" && moved.isFavorite)
    #expect(session.entries(inGroup: old.id).isEmpty)
    #expect(moved.modified >= entry.modified)
}

@MainActor
@Test func movingAnEntryToItsOwnGroupChangesNothing() async throws {
    let (session, old, _) = try await movingSession()
    let entry = try session.addEntry(VaultEntry(groupID: old.id, title: "Fake", values: [old.fields[0].id: "x"]))
    try session.moveEntry(id: entry.id, toGroup: old.id)
    #expect(session.entry(id: entry.id) == entry)
}

@MainActor
@Test func anEntryCantMoveToAMissingOrDeletedGroup() async throws {
    let (session, old, new) = try await movingSession()
    let entry = try session.addEntry(VaultEntry(groupID: old.id, title: "Fake"))
    #expect(throws: VaultError.unknownGroup) { try session.moveEntry(id: entry.id, toGroup: UUID()) }
    try session.moveGroupToTrash(id: new.id)
    #expect(throws: VaultError.unknownGroup) { try session.moveEntry(id: entry.id, toGroup: new.id) }
    #expect(throws: VaultError.notFound) { try session.moveEntry(id: UUID(), toGroup: old.id) }
    #expect(session.entry(id: entry.id)?.groupID == old.id)
}

@MainActor
@Test func aLockedVaultCantMoveEntries() async throws {
    let (session, old, new) = try await movingSession()
    let entry = try session.addEntry(VaultEntry(groupID: old.id, title: "Fake"))
    session.lock()
    #expect(throws: VaultError.locked) { try session.moveEntry(id: entry.id, toGroup: new.id) }
}
