/// Silicon Wallet's core: crypto, the domain model, the encrypted store, sync and the vault session.
///
/// Each area lives in its own folder (Crypto, Model, Store, Sync, Vault) and is filled in by the
/// build order in DESIGN.md §8.
public enum SiliconWalletKit {
    /// The vault format version written by this build.
    public static let formatVersion = 1
}
