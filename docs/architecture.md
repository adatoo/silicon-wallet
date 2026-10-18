# Architecture

A summary. [DESIGN.md](../DESIGN.md) has the full, agreed design; read it before changing anything.

## Shape

```
silicon-wallet/
├─ project.yml                  # XcodeGen source of SiliconWallet.xcodeproj (ADR-0001)
├─ App/                         # the multiplatform SwiftUI app target (iOS, iPadOS, macOS)
│  ├─ Shared/                   # scenes, NavigationSplitView UI, view models
│  ├─ iOS/  macOS/              # platform-only code, included per destination
│  └─ Resources/                # assets, privacy manifest
├─ Packages/SiliconWalletKit/   # all non-UI logic, unit-tested
│  └─ Sources/SiliconWalletKit/{Crypto,Model,Store,Sync,Vault}
├─ Tests/SiliconWalletTests/    # app-level tests
└─ Config/                      # xcconfigs; Version.xcconfig is generated from VERSION
```

## Boundaries

- The app target never touches ciphertext or CloudKit. It talks to `VaultSession` in
  SiliconWalletKit, which hands out plaintext domain objects only while the vault is unlocked.
- Every Group and Entry is sealed with AES-256-GCM under a random vault key, which is itself
  wrapped under a key derived from the master password with Argon2id (DESIGN.md §5).
- Locally, SwiftData holds ciphertext envelopes only (§6). Sync is `CKSyncEngine` against the
  private CloudKit database (§7, ADR-0004).

## Platforms

One app target with `supportedDestinations: [iOS, macOS]` and one bundle ID,
`com.datoos.silicon-wallet`, so the App Store sells it as a single universal purchase.
Minimum OS: iOS 26, iPadOS 26 and macOS 26.

## Commands and CI

`Taskfile.yml` is the only command surface. CI (`.github/workflows/ci.yml`) runs `task ci:linux`
on Linux and `task ci:mac` on the Mac runner, and the `CI Gate` job is the one required check.
The Mac runner has no GUI session, so it can't run app-hosted tests: it runs the package tests
and builds both platforms, and `task ci` adds the app-hosted tests locally.
