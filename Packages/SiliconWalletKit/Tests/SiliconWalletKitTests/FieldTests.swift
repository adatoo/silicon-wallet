import Foundation
import Testing

@testable import SiliconWalletKit

/// Encodes `value` as JSON without `key`, as a build from before that key existed wrote it.
private func json(_ value: some Encodable, removing key: String) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    object[key] = nil
    return try JSONSerialization.data(withJSONObject: object)
}

@Test func passwordsAndConcealedFieldsStartMonospaced() {
    #expect(!FieldTemplate(label: "Fake Name").isMonospaced)
    #expect(FieldTemplate(label: "Fake Password", kind: .password).isMonospaced)
    #expect(FieldTemplate(label: "Fake PIN", kind: .number, isConcealed: true).isMonospaced)
    #expect(FieldTemplate(label: "Fake Key", isMonospaced: true).isMonospaced)
    #expect(!FieldTemplate(label: "Fake Password", kind: .password, isMonospaced: false).isMonospaced)
    #expect(!CustomField(label: "Fake Note").isMonospaced)
    #expect(CustomField(label: "Fake Code", isConcealed: true).isMonospaced)
    #expect(CustomField(label: "Fake Serial", isMonospaced: true).isMonospaced)
}

@Test func fieldsFromOlderBuildsGetTheMonospacedDefault() throws {
    let decoder = JSONDecoder()
    let plain = try decoder.decode(
        FieldTemplate.self, from: json(FieldTemplate(label: "Fake Name", isMonospaced: true), removing: "isMonospaced"))
    #expect(!plain.isMonospaced)
    let secret = try decoder.decode(
        FieldTemplate.self,
        from: json(FieldTemplate(label: "Fake PIN", isConcealed: true, isMonospaced: false), removing: "isMonospaced"))
    #expect(secret.isMonospaced)

    let extra = try decoder.decode(
        CustomField.self,
        from: json(CustomField(label: "Fake Code", kind: .password, value: "fake-value"), removing: "isMonospaced"))
    #expect(extra.isMonospaced)
    #expect(extra.value == "fake-value")
}

@Test func theMonospacedChoiceRoundTrips() throws {
    let template = FieldTemplate(label: "Fake Key", isMonospaced: true)
    #expect(try JSONDecoder().decode(FieldTemplate.self, from: JSONEncoder().encode(template)) == template)
    let extra = CustomField(label: "Fake Password", kind: .password, isMonospaced: false, value: "fake-value")
    #expect(try JSONDecoder().decode(CustomField.self, from: JSONEncoder().encode(extra)) == extra)
}

@MainActor
@Test func theMonospacedChoiceSurvivesLockingTheVault() async throws {
    let session = try VaultSession(store: InMemoryVaultStore())
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let group = try session.addGroup(
        VaultGroup(name: "Fake Licences", fields: [FieldTemplate(label: "Fake Key", isMonospaced: true)]))
    let entry = try session.addEntry(
        VaultEntry(
            groupID: group.id, title: "Fake App",
            extraFields: [CustomField(label: "Fake Serial", isMonospaced: true, value: "FAKE-0000")]))

    session.lock()
    try await session.unlock(password: "fake-master")

    #expect(session.group(id: group.id)?.fields.first?.isMonospaced == true)
    #expect(session.entry(id: entry.id)?.extraFields.first?.isMonospaced == true)
}
