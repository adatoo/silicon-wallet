import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

/// Imports of the fake fixtures in `Fixtures/AcrylicWallet/` (all data there is fake).
private enum ImportFixture {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/AcrylicWallet")

    static func plan(_ name: String, _ password: String, existing: Set<String> = []) throws -> AcrylicImportPlan {
        try AcrylicImporter.plan(
            ciphertext: Data(contentsOf: directory.appendingPathComponent(name)), password: password,
            existingGroupNames: existing)
    }
}

private func value(_ entry: VaultEntry, _ label: String, in plan: AcrylicImportPlan) -> String? {
    guard let group = plan.groups.first(where: { $0.id == entry.groupID }),
        let field = group.fields.first(where: { $0.label == label })
    else { return nil }
    return entry.values[field.id]
}

@Test func vaultAImportsGroupsLabelsValuesAndFavourites() throws {
    let plan = try ImportFixture.plan("a.wallet", "fakepass")

    #expect(
        plan.groups.map(\.name) == ["Serial Numbers", "Web Passwords", "Credit Cards", "Fake Logins", "Fake Accounts"])
    let logins = try #require(plan.groups.first { $0.name == "Fake Logins" })
    #expect(logins.fields.map(\.label) == ["Login Email", "Member Number", "Support Phone"])
    #expect(logins.fields.map(\.kind) == [.email, .text, .phone])

    #expect(plan.entries.count == 5)
    let bank = try #require(plan.entries.first { $0.title == "Example Bank" })
    #expect(bank.isFavorite)
    #expect(value(bank, "Login Email", in: plan) == "fake.user@example.com")
    #expect(value(bank, "Member Number", in: plan) == "FAKE-000111")
    #expect(bank.notes == "Fake test entry for the Silicon Wallet migration spike.")
    #expect(bank.extraFields.isEmpty)
    #expect(plan.unlabelledValueCount == 0)

    // Wallet's own date, not the import time.
    #expect(bank.modified < Date(timeIntervalSince1970: 1_792_400_000))
}

@Test func builtInGroupsGetSuitableKindsAndConcealment() throws {
    let plan = try ImportFixture.plan("a.wallet", "fakepass")
    let web = try #require(plan.groups.first { $0.name == "Web Passwords" })
    #expect(web.fields.map(\.kind) == [.text, .password, .url])
    #expect(web.fields.map(\.isConcealed) == [false, true, false])

    let cards = try #require(plan.groups.first { $0.name == "Credit Cards" })
    #expect(cards.fields.map(\.label) == ["Number", "Security Code", "Expiry Date"])
    #expect(cards.fields.map(\.isConcealed) == [true, true, false])
    #expect(cards.icon == "creditcard")
}

@Test func vaultIBringsTheCardAndPasswordAcross() throws {
    let plan = try ImportFixture.plan("i.wallet", "fakepassword")
    let password = try #require(plan.entries.first { $0.title == "fake password" })
    #expect(value(password, "User Name", in: plan) == "fakeuser")
    #expect(value(password, "Password", in: plan) == "fakepassword")
    let card = try #require(plan.entries.first { $0.title == "fake card" })
    #expect(value(card, "Number", in: plan) == "4111 1111 1111 1111")
}

@Test func vaultFKeepsNonASCIIText() throws {
    let plan = try ImportFixture.plan("f.wallet", "fake-pässwörd-✓")
    let text = plan.entries.flatMap { [$0.title] + $0.values.values }.joined(separator: " ")
    #expect(text.contains("Ü") || text.contains("ü") || text.contains("ä"))
}

@Test func attachmentsOverTheLimitAreLeftOutAndCounted() throws {
    let reader = try AcrylicWalletReader(
        ciphertext: Data(contentsOf: ImportFixture.directory.appendingPathComponent("g.wallet")), password: "fakepass")
    let plan = try AcrylicImporter.plan(reader: reader, maximumAttachmentSize: 16)
    #expect(plan.attachments.isEmpty)
    #expect(plan.oversizedAttachmentCount == 1)
    #expect(plan.entries.count == 32)
}

@Test func vaultGBringsTheAttachment() throws {
    let plan = try ImportFixture.plan("g.wallet", "fakepass")
    #expect(plan.entries.count == 32)
    #expect(plan.attachments.count == 1)
    #expect(plan.missingAttachmentCount == 0)
    #expect(plan.oversizedAttachmentCount == 0)

    let attachment = try #require(plan.attachments.first)
    #expect(attachment.filename == "attachment-test.png")
    #expect(attachment.uti == "public.png")
    let holder = try #require(plan.entries.first { $0.id == attachment.entryID })
    #expect(holder.title == "Example Attachment Holder")
    let original = try Data(contentsOf: ImportFixture.directory.appendingPathComponent("attachment-test.png"))
    #expect(attachment.contents == original)
}

@Test func clashingGroupNamesGetASuffix() throws {
    let plan = try ImportFixture.plan("a.wallet", "fakepass", existing: ["Credit Cards", "credit cards (acrylic)"])
    #expect(plan.groups.contains { $0.name == "Credit Cards (Acrylic) 2" })
    #expect(!plan.groups.contains { $0.name == "Credit Cards" })
}

@Test func aWrongPasswordIsReported() throws {
    #expect(throws: AcrylicWalletError.wrongPasswordOrUnsupportedFile) {
        try ImportFixture.plan("a.wallet", "wrong")
    }
}

@MainActor
@Test func anImportLandsSealedInTheVault() async throws {
    let store = InMemoryVaultStore()
    let session = try VaultSession(store: store)
    try await session.createVault(password: "fake-master", kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    let plan = try ImportFixture.plan(
        "g.wallet", "fakepass", existing: Set(session.groups.map(\.name)))

    let counts = try session.importItems(plan)
    #expect(counts.entries == 32 && counts.attachments == 1)
    #expect(session.groups.count == 5 + plan.groups.count)

    let holder = try #require(session.entries.first { $0.title == "Example Attachment Holder" })
    let ref = try #require(holder.attachments.first)
    let original = try Data(contentsOf: ImportFixture.directory.appendingPathComponent("attachment-test.png"))
    #expect(try session.attachmentContents(ref) == original)

    session.lock()
    try await session.unlock(password: "fake-master")
    #expect(session.entries.count == 32)
    #expect(session.unreadableRecordCount == 0)
}

@Test func headerTemplatesConcealSecretsButNotLookalikes() {
    func concealed(_ title: String, group: String = "") -> Bool {
        AcrylicImporter.template(for: .init(uuid: "x", title: title, type: 0, contentType: 0), groupTitle: group)
            .isConcealed
    }
    #expect(concealed("PIN"))
    #expect(concealed("Card PIN"))
    #expect(concealed("CVV"))
    #expect(concealed("Licence Key"))
    #expect(concealed("Number", group: "Credit Cards"))
    #expect(!concealed("Number", group: "Serial Numbers"))
    #expect(!concealed("Shipping Address"))
    #expect(!concealed("Spinning Class"))
}

@Test func attachmentListsParse() {
    #expect(
        AcrylicPropertyListText.quotedStrings(afterEqualsIn: "\"array\" = (\n    \"A\",\n    \"B\"\n);") == ["A", "B"])
    #expect(AcrylicPropertyListText.quotedStrings(afterEqualsIn: "\"array\" = (\n);").isEmpty)
    #expect(AcrylicPropertyListText.quotedStrings(afterEqualsIn: "").isEmpty)
}
