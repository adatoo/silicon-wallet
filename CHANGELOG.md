# Changelog

All notable changes to Silicon Wallet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.15.0] - 2026-10-19

### Added

- The entry list can be grouped by the first letter of each title, with an A–Z index on
  iPhone and iPad. Turn it on or off with "Group by First Letter" in the list's View Options
  menu, or in the View menu on the Mac.

## [0.14.0] - 2026-10-19

### Changed

- On the Mac, Touch ID now appears inside the lock screen instead of in a separate floating
  panel. Start typing your password to skip it, or choose "Use Touch ID" to try again.

## [0.13.0] - 2026-10-18

### Added

- A release pipeline that builds, signs and uploads the iPhone, iPad and Mac app to App Store
  Connect for TestFlight and the App Store.

## [0.12.0] - 2026-10-18

### Added

- The App Store listing, support page and privacy policy.

### Fixed

- On iPhone and iPad, the Lock button and sync status were missing from the toolbar; they're now
  in the sidebar.
- On iPhone, the entry list now shows its title.

## [0.11.0] - 2026-10-18

### Added

- An access log in Settings shows when your vault was unlocked (and how), failed attempts,
  password changes, imports and saved copies. It's encrypted and stays on this device.
- Delete Vault, protected by your master password: remove it from iCloud and all your devices,
  or from this device only.
- An About screen with the version, licence and privacy summary.

## [0.10.0] - 2026-10-18

### Added

- Attachments: add files (or photos on iPhone and iPad, or drop files on the Mac) to any
  entry, view images, PDFs and text right in the app, open anything else in Quick Look, and
  save a copy when you need one. Each attachment is encrypted with its own key.

## [0.9.0] - 2026-10-18

### Added

- iCloud sync: your vault, including attachments, stays the same on your Mac, iPad and iPhone.
  Everything is encrypted before it leaves the device, so Apple can't read it.
- A new device finds the vault you already have in iCloud and asks for your master password.
- If two devices change the same entry at once, the later change wins and the other is kept as
  a "conflict copy", so nothing is lost.
- A sync indicator in the toolbar (tap to sync now) and sync status in Settings.

### Changed

- Attachments are limited to 100 MB each.

## [0.8.0] - 2026-10-18

### Added

- Silicon Wallet has its own icon: a silicon chip with a keyhole, with dark and tinted versions
  on iPhone and iPad. The app's accent colour matches it.

## [0.7.0] - 2026-10-18

### Added

- Import from Acrylic Wallet: choose your `.wallet` file (or a Wallet Database export), enter
  its old password, check the preview and import. Groups, field labels, entries, notes,
  favourites, dates and attachments all come across, and nothing is uploaded or saved
  unencrypted. You don't need Wallet installed.
- Setting up a new vault? Choose "I'm moving from Acrylic Wallet" to start empty and import
  straight away.

## [0.6.0] - 2026-10-18

### Added

- Unlock with Face ID or Touch ID. Your master password is still needed after a restart and
  at least every 7 days (you can change this).
- The vault locks itself after 5 minutes without use, when your Mac sleeps or its screen locks,
  and when you leave the app on iPhone and iPad. The app switcher shows a cover, not your vault.
- Copied values clear themselves from the clipboard after a minute, and when the vault locks.
- A password generator for random characters or easy-to-type word passphrases.
- Settings for locking, the clipboard and biometrics, and a way to change your master password.

## [0.5.0] - 2026-10-18

### Added

- The app: create a vault with a master password (with a strength meter), unlock it, and
  browse it in three columns: groups, entries and details.
- Add, edit, reorder and delete groups, each with its own icon and field template.
- Add, edit, favourite, search and delete entries. Move an entry to another group and every
  value comes with it.
- Concealed values stay hidden until you reveal them, and copy without showing.
- Keyboard shortcuts on the Mac: ⌘N new entry, ⇧⌘N new group, ⌘E edit, ⌃⌘L lock.

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
