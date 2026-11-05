import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for related entries (DESIGN.md §4). Every name and value is fake.
private let fastKDF = KDFParameters.generate(iterations: 1, memoryBytes: 8 << 10)

/// A fake bank's login and two accounts, nothing linked yet.
@MainActor
private func bankSession(
    store: InMemoryVaultStore = InMemoryVaultStore()
) async throws -> (VaultSession, login: VaultEntry, current: VaultEntry, deposit: VaultEntry) {
    let session = try VaultSession(store: store)
    try await session.createVault(password: "fake-master", starterGroups: false, kdf: fastKDF)
    let logins = try session.addGroup(VaultGroup(name: "Fake Logins"))
    let accounts = try session.addGroup(VaultGroup(name: "Fake Accounts"))
    let login = try session.addEntry(VaultEntry(groupID: logins.id, title: "Example Bank Online"))
    let current = try session.addEntry(VaultEntry(groupID: accounts.id, title: "Example Bank Current"))
    let deposit = try session.addEntry(VaultEntry(groupID: accounts.id, title: "Example Bank Deposit"))
    return (session, login, current, deposit)
}

@MainActor
private func titles(_ entries: [VaultEntry]) -> [String] { entries.map(\.title) }

// MARK: - Model

@Test func anEntryWrittenBeforeLinksDecodesWithNone() throws {
    let entry = VaultEntry(groupID: UUID(), title: "Fake", relatedIDs: [UUID()])
    var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
    #expect(object["relatedIDs"] != nil)
    object["relatedIDs"] = nil
    let decoded = try JSONDecoder().decode(VaultEntry.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(decoded.relatedIDs.isEmpty)
    #expect(decoded.title == "Fake" && decoded.id == entry.id)
}

@MainActor
@Test func linksSurviveSealingAndReopening() async throws {
    let store = InMemoryVaultStore()
    let (session, login, current, deposit) = try await bankSession(store: store)
    try session.setRelated([current.id, deposit.id], for: login.id)

    session.lock()
    let reopened = try VaultSession(store: store)
    try await reopened.unlock(password: "fake-master")
    #expect(reopened.entry(id: login.id)?.relatedIDs == [current.id, deposit.id])
}

// MARK: - Showing links

@MainActor
@Test func aLinkShowsOnBothSides() async throws {
    let (session, login, current, deposit) = try await bankSession()
    try session.setRelated([deposit.id, current.id], for: login.id)

    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Deposit", "Example Bank Current"])
    #expect(titles(session.relatedEntries(of: current.id)) == ["Example Bank Online"])
    #expect(titles(session.relatedEntries(of: deposit.id)) == ["Example Bank Online"])
    // Stored once: the accounts themselves weren't changed.
    #expect(session.entry(id: current.id)?.relatedIDs.isEmpty == true)
}

@MainActor
@Test func ownLinksComeFirstThenBacklinksByTitleEachOnce() async throws {
    let (session, login, current, deposit) = try await bankSession()
    try session.setRelated([deposit.id], for: login.id)
    try session.setRelated([login.id], for: deposit.id)
    try session.setRelated([login.id], for: current.id)

    // Deposit is both a link and a backlink, so it shows once, in the login's order.
    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Deposit", "Example Bank Current"])
}

@MainActor
@Test func anEntryInRecentlyDeletedIsHiddenUntilRestored() async throws {
    let (session, login, current, deposit) = try await bankSession()
    try session.setRelated([current.id, deposit.id], for: login.id)

    try session.moveEntryToTrash(id: current.id)
    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Deposit"])

    // Saving from the editor, which doesn't show it, keeps the hidden link.
    try session.updateEntry(try #require(session.entry(id: login.id)), related: [deposit.id])
    #expect(session.entry(id: login.id)?.relatedIDs == [deposit.id, current.id])

    try session.restoreEntry(id: current.id)
    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Deposit", "Example Bank Current"])
}

@MainActor
@Test func anEntryDeletedForGoodIsHidden() async throws {
    let (session, login, current, deposit) = try await bankSession()
    try session.setRelated([current.id, deposit.id], for: login.id)
    try session.moveEntryToTrash(id: current.id)
    try session.deleteEntryPermanently(id: current.id)

    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Deposit"])
    try session.setRelated([deposit.id], for: login.id)
    #expect(session.entry(id: login.id)?.relatedIDs == [deposit.id])
}

// MARK: - Changing links

@MainActor
@Test func unlinkingFromEitherSideRemovesTheLink() async throws {
    let (session, login, current, deposit) = try await bankSession()
    try session.setRelated([current.id, deposit.id], for: login.id)

    // From the account, where the login is a backlink.
    try session.setRelated([], for: current.id)
    #expect(session.entry(id: login.id)?.relatedIDs == [deposit.id])
    #expect(session.relatedEntries(of: current.id).isEmpty)

    // From the login, where deposit is its own link.
    try session.setRelated([], for: login.id)
    #expect(session.relatedEntries(of: deposit.id).isEmpty)
}

@MainActor
@Test func savingDropsSelfLinksRepeatsAndUnknownIDs() async throws {
    let (session, login, current, _) = try await bankSession()
    try session.setRelated([login.id, current.id, current.id, UUID()], for: login.id)
    #expect(session.entry(id: login.id)?.relatedIDs == [current.id])

    let new = try session.addEntry(
        VaultEntry(groupID: login.groupID, title: "Fake New", relatedIDs: [UUID(), current.id]))
    #expect(new.relatedIDs == [current.id])
}

@MainActor
@Test func otherSavesLeaveLinksAlone() async throws {
    let (session, login, current, _) = try await bankSession()
    try session.setRelated([login.id], for: current.id)
    try session.setFavorite(true, entryID: login.id)
    try session.updateEntry(try #require(session.entry(id: login.id)))
    #expect(session.entry(id: current.id)?.relatedIDs == [login.id])
    #expect(titles(session.relatedEntries(of: login.id)) == ["Example Bank Current"])
}

// MARK: - Export and import

@MainActor
@Test func linksSurviveAnExportAndImport() async throws {
    let (source, login, current, deposit) = try await bankSession()
    try source.setRelated([current.id, deposit.id], for: login.id)
    let json = try source.exportJSON()

    let target = try VaultSession(store: InMemoryVaultStore())
    try await target.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    try target.importItems(try ExportFile.plan(json: json))
    #expect(target.entry(id: login.id)?.relatedIDs == [current.id, deposit.id])
    #expect(titles(target.relatedEntries(of: deposit.id)) == ["Example Bank Online"])
}

@MainActor
@Test func anImportDropsLinksToEntriesTheVaultWontHave() async throws {
    let (source, login, current, _) = try await bankSession()
    let missing = UUID()
    try source.setRelated([current.id], for: login.id)
    var document = try source.exportDocument()
    let index = try #require(document.entries.firstIndex { $0.id == login.id })
    document.entries[index].related = [missing, current.id]
    document.entries.removeAll { $0.id == current.id }

    let target = try VaultSession(store: InMemoryVaultStore())
    try await target.createVault(password: "fake-other", starterGroups: false, kdf: fastKDF)
    try target.importItems(try ExportFile.plan(json: ExportFile.json(document)))
    #expect(target.entry(id: login.id)?.relatedIDs.isEmpty == true)
}

@MainActor
@Test func anEntryWithoutLinksExportsNoRelatedKey() async throws {
    let (source, _, _, _) = try await bankSession()
    let text = try #require(String(data: try source.exportJSON(), encoding: .utf8))
    #expect(!text.contains("\"related\""))
}
