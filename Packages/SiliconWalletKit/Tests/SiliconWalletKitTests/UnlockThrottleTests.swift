import Foundation
import Testing

@testable import SiliconWalletKit

/// Tests for slowing down wrong master passwords (DESIGN.md §5). Every password is fake.
@MainActor
private final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("UnlockThrottleTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func theWaitStartsAfterFiveFailuresAndDoublesUpToAnHour() {
    #expect((0...4).map { UnlockThrottle.delay(afterFailures: $0) } == [0, 0, 0, 0, 0])
    #expect((5...12).map { UnlockThrottle.delay(afterFailures: $0) } == [60, 120, 240, 480, 960, 1920, 3600, 3600])
    #expect(UnlockThrottle.delay(afterFailures: 10_000) == 3600)
}

@MainActor
@Test func failuresMakeTheNextAttemptWaitUntilASuccess() {
    let clock = FakeClock()
    let throttle = UnlockThrottle(directory: nil) { clock.now }
    for _ in 0..<4 { throttle.recordFailure() }
    #expect(throttle.nextAttempt() == nil)
    #expect(throttle.attemptsBeforeDelay == 1)

    throttle.recordFailure()
    #expect(throttle.attemptsBeforeDelay == 0)
    #expect(throttle.nextAttempt() == clock.now.addingTimeInterval(60))
    clock.advance(59)
    #expect(throttle.nextAttempt() != nil)
    clock.advance(1)
    #expect(throttle.nextAttempt() == nil)

    throttle.recordFailure()
    #expect(throttle.nextAttempt() == clock.now.addingTimeInterval(120))
    throttle.reset()
    #expect(throttle.nextAttempt() == nil && throttle.attemptsBeforeDelay == UnlockThrottle.freeAttempts)
}

@MainActor
@Test func settingTheClockBackDoesntShortenTheWait() {
    let clock = FakeClock()
    let throttle = UnlockThrottle(directory: nil) { clock.now }
    for _ in 0..<5 { throttle.recordFailure() }
    clock.advance(-3600)
    #expect(throttle.nextAttempt() == clock.now.addingTimeInterval(60))
}

@MainActor
@Test func theWaitSurvivesARelaunchButNotASuccess() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = FakeClock()
    let first = UnlockThrottle(directory: directory) { clock.now }
    for _ in 0..<6 { first.recordFailure() }

    let relaunched = UnlockThrottle(directory: directory) { clock.now }
    #expect(relaunched.nextAttempt() == clock.now.addingTimeInterval(120))
    relaunched.reset()
    #expect(UnlockThrottle(directory: directory) { clock.now }.nextAttempt() == nil)
}

@MainActor
private func throttledSession(_ clock: FakeClock) async throws -> VaultSession {
    let session = try VaultSession(
        store: InMemoryVaultStore(), unlockThrottle: UnlockThrottle(directory: nil) { clock.now })
    try await session.createVault(
        password: "fake-master", starterGroups: false, kdf: .generate(iterations: 1, memoryBytes: 8 << 10))
    session.lock()
    return session
}

@MainActor
@Test func theSessionRefusesEvenTheRightPasswordDuringAWait() async throws {
    let clock = FakeClock()
    let session = try await throttledSession(clock)
    for _ in 0..<5 {
        await #expect(throws: VaultError.wrongPassword) { try await session.unlock(password: "fake-wrong") }
    }
    let until = clock.now.addingTimeInterval(60)
    #expect(session.nextPasswordAttempt == until)
    await #expect(throws: VaultError.tooManyAttempts(until: until)) {
        try await session.unlock(password: "fake-master")
    }
    #expect(!session.isUnlocked)

    clock.advance(60)
    try await session.unlock(password: "fake-master")
    #expect(session.isUnlocked)
    #expect(session.nextPasswordAttempt == nil && session.passwordAttemptsBeforeDelay == UnlockThrottle.freeAttempts)
}

@MainActor
@Test func aBiometricUnlockWorksDuringAWaitAndClearsIt() async throws {
    let clock = FakeClock()
    let session = try await throttledSession(clock)
    try await session.unlock(password: "fake-master")
    let key = try #require(session.vaultKeyForBiometricUnlock())
    session.lock()
    for _ in 0..<5 { _ = try? await session.unlock(password: "fake-wrong") }
    #expect(session.nextPasswordAttempt != nil)

    try session.unlock(vaultKey: key)
    #expect(session.isUnlocked && session.nextPasswordAttempt == nil)
}

@MainActor
@Test func checkingThePasswordWhileUnlockedIsntHeldBack() async throws {
    let clock = FakeClock()
    let session = try await throttledSession(clock)
    try await session.unlock(password: "fake-master")
    for _ in 0..<6 { #expect(try await !session.verifyPassword("fake-wrong")) }
    #expect(try await session.verifyPassword("fake-master"))
    #expect(session.nextPasswordAttempt == nil)
}
