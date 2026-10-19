import CryptoKit
import Foundation

/// When this device first saw each item in Recently Deleted (DESIGN.md §5). An item is deleted for
/// good only after this device has shown it for `VaultSession.minimumNotice`, so an old copy
/// replayed through iCloud, or a deletion date from a device whose clock is far behind, can't
/// delete anything at once.
///
/// Local to this device, never synced, and sealed under the vault key like the access log. With
/// no directory it lives in memory only.
@MainActor
public final class TrashLedger {
    private let url: URL?
    private var firstSeen: [UUID: Date] = [:]
    /// A fixed ID for the ledger's associated data, so its sealed bytes can't pass as a record.
    private static let recordID = UUID(uuidString: "00000000-0000-0000-0000-00000000D31E")!

    public init(directory: URL?) {
        url = directory?.appendingPathComponent("TrashLedger.sealed")
    }

    /// When this device first saw `id` in Recently Deleted, if it has.
    func firstSeen(_ id: UUID) -> Date? { firstSeen[id] }

    /// Reads the sealed ledger. A missing or unreadable one starts empty, which only delays
    /// deletions.
    func load(key: SymmetricKey) {
        guard let url else { return }
        firstSeen = [:]
        if let sealed = try? Data(contentsOf: url),
            let plaintext = try? RecordSealer.open(sealed, recordID: Self.recordID, key: key),
            let decoded = try? JSONDecoder().decode([UUID: Date].self, from: plaintext)
        {
            firstSeen = decoded
        }
    }

    /// Notes the items in Recently Deleted now: new ones are first seen at `now`, and ones that
    /// have left are forgotten.
    func update(trashed ids: Set<UUID>, now: Date, key: SymmetricKey) {
        var updated = firstSeen.filter { ids.contains($0.key) }
        for id in ids where updated[id] == nil { updated[id] = now }
        guard updated != firstSeen else { return }
        firstSeen = updated
        save(key: key)
    }

    /// Drops the ledger from memory, on lock.
    func forget() { firstSeen = [:] }

    /// Deletes the ledger, with the vault.
    func clear() {
        firstSeen = [:]
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func save(key: SymmetricKey) {
        guard let url, let plaintext = try? JSONEncoder().encode(firstSeen),
            let sealed = try? RecordSealer.seal(plaintext, recordID: Self.recordID, key: key)
        else { return }
        #if os(iOS)
            try? sealed.write(to: url, options: [.atomic, .completeFileProtection])
        #else
            try? sealed.write(to: url, options: .atomic)
        #endif
    }
}
