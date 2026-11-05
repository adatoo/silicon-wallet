import Foundation

/// Slows down guessing the master password at the lock screen (DESIGN.md §5). The first
/// `freeAttempts` wrong passwords cost nothing extra; after that each one makes the next attempt
/// wait, starting at `firstDelay` and doubling up to `maximumDelay`. Any successful unlock clears
/// it. Face ID and Touch ID aren't held back: they have their own limits.
///
/// It holds only a count and a time, so it's stored in the clear, in the vault's folder: local to
/// this device, never synced, and kept across launches. With no directory it lives in memory only.
/// It slows guessing in the app; a copy of the vault's files is protected by Argon2id instead.
@MainActor
public final class UnlockThrottle {
    public nonisolated static let freeAttempts = 5
    public nonisolated static let firstDelay: TimeInterval = 60
    public nonisolated static let maximumDelay: TimeInterval = 60 * 60

    private struct State: Codable, Equatable {
        var failures = 0
        var lastFailure: Date?
    }

    private let url: URL?
    private let now: () -> Date
    private var state: State

    /// - Parameter now: the clock, for tests.
    public init(directory: URL?, now: @escaping () -> Date = { .now }) {
        url = directory?.appendingPathComponent("UnlockThrottle.json")
        self.now = now
        state =
            url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(State.self, from: $0) }
            ?? State()
    }

    /// How long to wait after `failures` wrong passwords in a row before trying again.
    public nonisolated static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures >= freeAttempts else { return 0 }
        let doublings = min(failures - freeAttempts, 16)
        return min(firstDelay * Double(1 << doublings), maximumDelay)
    }

    /// Wrong passwords left before one makes the next attempt wait.
    public var attemptsBeforeDelay: Int { max(0, Self.freeAttempts - state.failures) }

    /// When the next password attempt may be made, or nil if it may be made now. A clock set back
    /// before the last failure counts the wait from now, so it can't cut the wait short.
    public func nextAttempt() -> Date? {
        guard let lastFailure = state.lastFailure else { return nil }
        let delay = Self.delay(afterFailures: state.failures)
        let current = now()
        let next = min(lastFailure, current).addingTimeInterval(delay)
        return next > current ? next : nil
    }

    func recordFailure() {
        state.failures += 1
        state.lastFailure = now()
        save()
    }

    func reset() {
        guard state != State() else { return }
        state = State()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(state) else { return }
        #if os(iOS)
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try? data.write(to: url, options: .atomic)
        #endif
    }
}
