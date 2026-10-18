import CryptoKit
import Foundation
import Testing

@testable import SiliconWalletKit

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("AccessLogTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Test func theLogRoundTripsSealed() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = VaultKey.generate()
    let log = AccessLog(directory: directory)

    log.record(AccessEvent(date: Date(timeIntervalSince1970: 1), kind: .exported, detail: "fake-scan.png"), key: key)
    log.record(AccessEvent(date: Date(timeIntervalSince1970: 2), kind: .unlockedWithPassword), key: key)

    let events = log.load(key: key)
    #expect(events.map(\.kind) == [.unlockedWithPassword, .exported])
    #expect(events.last?.detail == "fake-scan.png")
    #expect(AccessLog(directory: directory).load(key: VaultKey.generate()).isEmpty)

    let onDisk = try Data(contentsOf: directory.appendingPathComponent("AccessLog.sealed"))
    #expect(onDisk.range(of: Data("fake-scan.png".utf8)) == nil)
    #expect(onDisk.range(of: Data("exported".utf8)) == nil)
}

@MainActor
@Test func failedUnlocksWaitInThePendingFileUntilTheNextUnlock() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = VaultKey.generate()
    let log = AccessLog(directory: directory)

    log.recordWhileLocked(.failedUnlock, date: Date(timeIntervalSince1970: 10))
    log.recordWhileLocked(.failedUnlock, date: Date(timeIntervalSince1970: 11))
    let pendingURL = directory.appendingPathComponent("AccessLog.pending.json")
    #expect(FileManager.default.fileExists(atPath: pendingURL.path))

    log.record(AccessEvent(date: Date(timeIntervalSince1970: 12), kind: .unlockedWithPassword), key: key)
    #expect(log.load(key: key).map(\.kind) == [.unlockedWithPassword, .failedUnlock, .failedUnlock])
    #expect(!FileManager.default.fileExists(atPath: pendingURL.path))
}

@MainActor
@Test func theLogKeepsOnlyTheNewestEvents() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let key = VaultKey.generate()
    let log = AccessLog(directory: directory)
    for index in 0..<(AccessLog.maximumEvents + 5) {
        log.record(AccessEvent(date: Date(timeIntervalSince1970: Double(index)), kind: .unlockedWithPassword), key: key)
    }
    let events = log.load(key: key)
    #expect(events.count == AccessLog.maximumEvents)
    #expect(events.first?.date == Date(timeIntervalSince1970: Double(AccessLog.maximumEvents + 4)))
}

@MainActor
@Test func theSessionRecordsWhatHappens() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = InMemoryVaultStore()
    let session = try VaultSession(store: store, accessLog: AccessLog(directory: directory))
    let kdf = KDFParameters.generate(iterations: 1, memoryBytes: 8 << 10)
    try await session.createVault(password: "fake-master", kdf: kdf)
    let key = try #require(session.vaultKeyForBiometricUnlock())
    session.lock()

    await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: "wrong") }
    try await session.unlock(password: "fake-master")
    try session.unlock(vaultKey: key)
    try await session.changePassword(current: "fake-master", new: "fake-new", kdf: kdf)
    session.recordAccess(.exported, detail: "fake.pdf")

    let kinds = session.accessEvents().map(\.kind)
    #expect(
        Set(kinds) == [
            .vaultCreated, .failedUnlock, .unlockedWithPassword, .unlockedWithBiometrics, .passwordChanged, .exported,
        ])

    session.lock()
    #expect(session.accessEvents().isEmpty)
    try session.deleteVault()
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("AccessLog.sealed").path))
}
