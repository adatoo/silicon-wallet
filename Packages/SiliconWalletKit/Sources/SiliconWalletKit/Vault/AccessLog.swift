import CryptoKit
import Foundation

/// One thing that happened to the vault on this device (DESIGN.md §5).
public struct AccessEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case unlockedWithPassword
        case unlockedWithBiometrics
        case failedUnlock
        case passwordChanged
        case imported
        case exported
        case vaultCreated
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    /// Extra detail, such as an exported file's name. Only ever stored sealed.
    public var detail: String?

    public init(id: UUID = UUID(), date: Date = .now, kind: Kind, detail: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.detail = detail
    }
}

/// The access log: local to this device, never synced, and sealed under the vault key.
///
/// Failed unlocks happen while the vault is locked, when there's no key to seal with, so they go
/// to a small pending file holding only the event kind and time. The next unlock seals them into
/// the log and deletes the pending file.
@MainActor
public final class AccessLog {
    public static let maximumEvents = 1_000

    private let sealedURL: URL
    private let pendingURL: URL
    /// A fixed ID for the log's associated data, so its sealed bytes can't pass as a record.
    private static let recordID = UUID(uuidString: "00000000-0000-0000-0000-00000000A10C")!

    public init(directory: URL) {
        sealedURL = directory.appendingPathComponent("AccessLog.sealed")
        pendingURL = directory.appendingPathComponent("AccessLog.pending.json")
    }

    /// Records an event while the vault is locked. Details are dropped: nothing but the kind and
    /// time is written in the clear.
    public func recordWhileLocked(_ kind: AccessEvent.Kind, date: Date = .now) {
        var pending = loadPending()
        pending.append(AccessEvent(date: date, kind: kind))
        if let data = try? JSONEncoder().encode(Array(pending.suffix(Self.maximumEvents))) {
            try? data.write(to: pendingURL, options: Self.writeOptions)
        }
    }

    /// Records an event with the vault unlocked, folding in any pending events first.
    public func record(_ event: AccessEvent, key: SymmetricKey) {
        var events = load(key: key)
        events.append(event)
        save(events, key: key)
    }

    /// Every event, newest first. Pending events are sealed into the log as a side effect.
    public func load(key: SymmetricKey) -> [AccessEvent] {
        var events: [AccessEvent] = []
        if let sealed = try? Data(contentsOf: sealedURL),
            let plaintext = try? RecordSealer.open(sealed, recordID: Self.recordID, key: key),
            let decoded = try? JSONDecoder().decode([AccessEvent].self, from: plaintext)
        {
            events = decoded
        }
        let pending = loadPending()
        if !pending.isEmpty {
            events += pending
            save(events, key: key)
            try? FileManager.default.removeItem(at: pendingURL)
        }
        return events.sorted { $0.date > $1.date }
    }

    /// Deletes the whole log.
    public func clear() {
        try? FileManager.default.removeItem(at: sealedURL)
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private func save(_ events: [AccessEvent], key: SymmetricKey) {
        let kept = Array(events.sorted { $0.date < $1.date }.suffix(Self.maximumEvents))
        guard let plaintext = try? JSONEncoder().encode(kept),
            let sealed = try? RecordSealer.seal(plaintext, recordID: Self.recordID, key: key)
        else { return }
        try? sealed.write(to: sealedURL, options: Self.writeOptions)
    }

    private func loadPending() -> [AccessEvent] {
        guard let data = try? Data(contentsOf: pendingURL) else { return [] }
        return (try? JSONDecoder().decode([AccessEvent].self, from: data)) ?? []
    }

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtection]
        #else
            .atomic
        #endif
    }
}
