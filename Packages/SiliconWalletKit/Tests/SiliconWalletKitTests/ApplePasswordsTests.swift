import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for keeping a login's password in Apple Passwords (DESIGN.md §3). Every value is fake.
private let fastKDF = KDFParameters.generate(iterations: 1, memoryBytes: 8 << 10)

@MainActor
private func loginSession() async throws -> (VaultSession, VaultGroup, VaultEntry) {
    let session = try VaultSession(store: InMemoryVaultStore())
    try await session.createVault(password: "fake-master", starterGroups: false, kdf: fastKDF)
    let group = try session.addGroup(
        VaultGroup(
            name: "Fake Logins",
            fields: [
                FieldTemplate(label: "Username"), FieldTemplate(label: "Password", kind: .password, isConcealed: true),
                FieldTemplate(label: "Website", kind: .url),
            ]))
    let username = group.fields[0].id
    let entry = try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Example Bank Online", values: [username: "fake-user"],
            extraFields: [CustomField(label: "Memorable Information", isConcealed: true, value: "fake-memorable")],
            passwordInApplePasswords: true))
    return (session, group, entry)
}

@Test func anEntryWrittenBeforeTheMarkerKeepsItsPasswordHere() throws {
    let entry = VaultEntry(groupID: UUID(), title: "Fake", passwordInApplePasswords: true)
    var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    #expect(object["passwordInApplePasswords"] as? Bool == true)
    object["passwordInApplePasswords"] = nil
    let decoded = try JSONDecoder().decode(VaultEntry.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(!decoded.passwordInApplePasswords)
    #expect(decoded.title == "Fake" && decoded.id == entry.id)
}

@Test func onlyPasswordFieldsAreKeptInApplePasswords() {
    let group = VaultGroup(
        name: "Fake",
        fields: [
            FieldTemplate(label: "Username"), FieldTemplate(label: "Password", kind: .password, isConcealed: true),
            FieldTemplate(label: "PIN", kind: .number, isConcealed: true),
        ])
    #expect(group.passwordFieldIDs == [group.fields[1].id])
    #expect(VaultGroup(name: "Fake Notes").passwordFieldIDs.isEmpty)
}

@MainActor
@Test func theMarkerAndTheOtherDetailsSurviveAnExportAndImport() async throws {
    let (source, _, entry) = try await loginSession()
    let json = try source.exportJSON()
    let text = try #require(String(data: json, encoding: .utf8))
    #expect(text.contains("\"inApplePasswords\""))

    let target = try VaultSession(store: InMemoryVaultStore())
    try await target.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    try target.importItems(try ExportFile.plan(json: json))
    let imported = try #require(target.entry(id: entry.id))
    #expect(imported.passwordInApplePasswords)
    #expect(imported.extraFields.first?.value == "fake-memorable")
}

@MainActor
@Test func anUnmarkedEntryExportsNoMarker() async throws {
    let (source, group, _) = try await loginSession()
    _ = try source.addEntry(VaultEntry(groupID: group.id, title: "Example Shop"))
    var document = try source.exportDocument()
    #expect(document.entries.first { $0.title == "Example Shop" }?.inApplePasswords == nil)
    // A file from before the marker reads as unmarked.
    for index in document.entries.indices { document.entries[index].inApplePasswords = nil }
    let target = try VaultSession(store: InMemoryVaultStore())
    try await target.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    try target.importItems(try ExportFile.plan(json: ExportFile.json(document)))
    #expect(target.entries.allSatisfy { !$0.passwordInApplePasswords })
}
