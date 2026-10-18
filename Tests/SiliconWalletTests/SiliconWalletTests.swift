import Foundation
import SiliconWalletKit
import Testing

@testable import SiliconWallet

@Test func appLinksTheKit() {
    #expect(SiliconWalletKit.formatVersion >= 1)
}

/// An unlocked in-memory vault with fake entries, for testing the app's view-model logic.
@MainActor
private func makeModel() async throws -> AppModel {
    let model = AppModel.launch(arguments: ["-InMemoryVault"])
    let session = try #require(model.session)
    try await session.createVault(password: "fake-master", kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let logins = try #require(session.groups.first { $0.name == "Logins" })
    let cards = try #require(session.groups.first { $0.name == "Credit Cards" })
    try session.addEntry(
        VaultEntry(groupID: logins.id, title: "Example Bank", values: [logins.fields[0].id: "fake.user"]))
    try session.addEntry(VaultEntry(groupID: logins.id, title: "Example Shop", isFavorite: true))
    try session.addEntry(VaultEntry(groupID: cards.id, title: "Example Card"))
    return model
}

@MainActor
@Test func theEntryListFollowsTheSidebarAndSearch() async throws {
    let model = try await makeModel()
    let session = try #require(model.session)
    let logins = try #require(session.groups.first { $0.name == "Logins" })

    #expect(model.visibleEntries.map(\.title) == ["Example Bank", "Example Card", "Example Shop"])

    model.sidebarSelection = .favorites
    #expect(model.visibleEntries.map(\.title) == ["Example Shop"])

    model.sidebarSelection = .group(logins.id)
    #expect(model.visibleEntries.map(\.title) == ["Example Bank", "Example Shop"])
    #expect(model.title(for: .group(logins.id)) == "Logins")

    model.searchText = "fake.user"
    #expect(model.visibleEntries.map(\.title) == ["Example Bank"])
}

@MainActor
@Test func deletingTheSelectedGroupResetsTheSelection() async throws {
    let model = try await makeModel()
    let session = try #require(model.session)
    let cards = try #require(session.groups.first { $0.name == "Credit Cards" })
    let card = try #require(session.entries.first { $0.title == "Example Card" })

    model.sidebarSelection = .group(cards.id)
    model.entrySelection = card.id
    model.deleteGroup(cards.id)

    #expect(model.sidebarSelection == .all)
    #expect(model.entrySelection == nil)
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func lockingClearsTheSelectionAndSearch() async throws {
    let model = try await makeModel()
    model.entrySelection = model.visibleEntries.first?.id
    model.searchText = "bank"
    model.lock()

    #expect(model.session?.state == .locked)
    #expect(model.entrySelection == nil && model.searchText.isEmpty)
    #expect(model.visibleEntries.isEmpty)
}

@MainActor
@Test func errorsBecomeReadableMessages() async throws {
    let model = try await makeModel()
    model.perform { throw VaultError.wrongPassword }
    #expect(model.errorMessage == "That password is wrong.")
}

@Test func fieldLinksSuitTheirKind() {
    #expect(FieldKind.url.link(for: "example.com")?.absoluteString == "https://example.com")
    #expect(FieldKind.url.link(for: "https://example.com/x")?.absoluteString == "https://example.com/x")
    #expect(FieldKind.email.link(for: "fake@example.com")?.absoluteString == "mailto:fake@example.com")
    #expect(FieldKind.phone.link(for: "+44 20 0000 0000")?.absoluteString == "tel:+442000000000")
    #expect(FieldKind.text.link(for: "anything") == nil)
}
