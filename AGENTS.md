# Silicon Wallet — project instructions

Read `DESIGN.md` before starting work; it holds all agreed decisions. If a change departs
from it, update `DESIGN.md` in the same change.

Git workflow and general project hygiene follow the user-level engineering standards
(`~/code/engineering-standards/AGENTS.md`). This file only adds project-specific rules.

## Repo facts
- Owner `adatoo`; `gh` uses the personal account through `GH_CONFIG_DIR` in `.envrc`.
- **Single version source:** `VERSION`. `task version:sync` writes it into
  `Config/Version.xcconfig`, and both change in the release commit (ADR-0003).
- The Xcode project is generated: edit `project.yml`, run `task generate`, and commit both
  (ADR-0001). Never hand-edit `SiliconWallet.xcodeproj` or `App/Info.plist`.
- ADRs: `docs/adr/`. Release roadmap: `docs/app-store-release.md`.
- The shared workflows (`auto-merge`, `issue-link`, `tag-on-merge`, `version-bump`) are vendored
  from engineering-standards v0.6.0. The repo is public (since 2026-10-20), so CI uses
  GitHub-hosted runners only; never add self-hosted runners back (ADR-0007).

## Build and test
Every command is a `task`; run `task` to list them.
- `task test:kit`: the SiliconWalletKit package tests.
- `task test:macos` and `task test:ios`: app and package tests on macOS and on the iOS
  Simulator (default `iPhone 17`; override with `IOS_SIM='…'`, see
  `xcrun simctl list devices available`).
- `task build`: both platforms. `task dev`: build and open the Mac app (ad-hoc signed, no iCloud).
- `task fmt` / `task fmt:check`: swift-format (`.swift-format`).
- `task cloudkit:export`, `cloudkit:validate`, `cloudkit:deploy`: the CloudKit schema in
  `CloudKit/schema.ckdb` (needs a management token in the keychain; deploy before TestFlight).
- `task icon`: redraw the app icon. `task screenshots`: App Store screenshots from the simulators.
- `task release` (or `release:archive` / `release:upload` with `PLATFORM=ios|macos`): upload to
  App Store Connect. The `release` workflow runs it for every version tag once the API key
  secrets exist (docs/app-store-release.md, B0).
- `task ci`: everything CI runs, plus the app-hosted tests. Run it before pushing.
  CI runs only the package tests and both builds (`task ci:mac`); `test:macos` and
  `test:ios` run locally.
- A change is done only when the package tests and both platform builds pass.

## Code rules
- Swift 6 language mode, strict concurrency. SwiftUI only; AppKit/UIKit only for small platform gaps.
- All non-UI logic lives in SiliconWalletKit. The app target never handles ciphertext or CloudKit.
- Dependencies: only libsodium/swift-sodium (Argon2id). Ask before adding any other.

## Security rules (non-negotiable)
- Never write plaintext vault data to disk, UserDefaults, logs, caches, iCloud or crash reports.
- Only ID, record type, modified date, schema version and ciphertext length may be unencrypted.
- Use CryptoKit AES-GCM with the record ID as associated data. Never hand-roll crypto primitives.
- Biometric key in Keychain: `.biometryCurrentSet`, `WhenUnlockedThisDeviceOnly`, never synced.
- Never use real secrets in tests or fixtures; use obviously fake data.
- Crypto and Vault code requires unit tests, including wrong-password and tampered-ciphertext cases.

## Build order
Follow DESIGN.md §8. Current step: 8 (settings, access log, polish, App Store assets). Steps 1–7
are done: crypto (ADR-0006), the model and `VaultSession`, the SwiftData store, the SwiftUI UI,
lock UX, CloudKit sync and attachments.

## Do not
- Copy anything from Acrylic Wallet (name, icon, artwork, code), or bundle/load its SQLite SEE library.
- Use SwiftData's CloudKit integration — sync is `CKSyncEngine` only.
- Build export or the AutoFill extension until the user asks (DESIGN.md §9). Acrylic import
  exists (`SiliconWalletKit/AcrylicImport`, ADR-0005).
