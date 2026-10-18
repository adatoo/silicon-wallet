# Changelog

All notable changes to Silicon Wallet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-10-18

### Added

- Your vault is saved on the device and survives restarts. It holds only encrypted records,
  and attachments are kept as separately encrypted files.

## [0.3.0] - 2026-10-18

### Added

- Vaults: create one with a master password, lock and unlock it, and change the password
  without re-encrypting anything.
- Groups with their own field templates, entries with extra fields, notes, favourites and
  attachments, and search that ignores case and accents but never looks inside concealed
  fields.
- New vaults start with Logins, Credit Cards, Bank Accounts, Software Licences and Secure Notes
  groups, all editable.

## [0.2.0] - 2026-10-18

### Added

- The encryption at the heart of every vault: your master password is stretched with Argon2id
  into a key that unlocks a random vault key, and each group, entry and attachment is sealed
  with AES-256-GCM under its own ID, so nothing can be read or swapped without the password.
- Passwords with accented letters unlock the same vault however they were typed.

## [0.1.4] - 2026-10-18

### Added

- `SiliconWalletKit` can decrypt Acrylic Wallet 3.5 `.wallet` files natively: the format
  (AES-256-OFB, no per-file salt) was recovered by black-box known-plaintext analysis of fake
  fixtures, with no SEE licence, no disassembly and no Acrylic code (ADR-0005).

## [0.1.3] - 2026-10-18

### Changed

- The App Store name "Silicon Wallet" is reserved for iPhone, iPad and Mac, and the release
  roadmap records the App Store Connect record.

## [0.1.2] - 2026-10-18

### Changed

- The app's bundle ID is now `com.datoos.silicon-wallet`, with the iCloud container
  `iCloud.com.datoos.silicon-wallet`.

## [0.1.1] - 2026-10-15

### Changed

- CI on the self-hosted Mac runner now runs the package tests and builds both platforms. The
  app-hosted tests need a GUI session, so they run locally as part of `task ci`.

## [0.1.0] - 2026-10-15

### Added

- The project: a multiplatform SwiftUI app for iPhone, iPad and Mac (iOS 26 and macOS 26),
  with a placeholder three-column window, and the `SiliconWalletKit` package that will hold
  all of the vault logic.
- iCloud (CloudKit) and push entitlements, the macOS App Sandbox, and a privacy manifest that
  declares no data collection.
- `task` commands for building, testing, formatting and linting, git hooks, and CI on
  GitHub Actions.
