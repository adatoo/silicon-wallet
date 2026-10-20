# Changelog

All notable changes to Silicon Wallet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.27.2] - 2026-10-20

### Fixed

- A device moving from a development build to TestFlight uploads its vault to CloudKit
  Production instead of waiting for each record to change.

## [0.27.1] - 2026-10-20

### Fixed

- On the Mac lock screen, Use Touch ID after Use Password goes back to Touch ID instead of
  showing the password field and Touch ID together.

## [0.27.0] - 2026-10-20

### Changed

- With Face ID or Touch ID on, the lock screen leads with them and a Use Password button; the
  password field shows only when asked for, or when the Face ID or Touch ID prompt is cancelled
  or fails.

## [0.26.0] - 2026-10-20

### Changed

- Face ID and Touch ID unlock every time once they're on, including after a restart, instead of
  asking for the master password every few days. Setup offers them, and a password unlock on a
  device where they're off offers them once.
- Every 30 days you're asked to check you still remember your master password; you can skip it
  for a week.
- After the faces or fingerprints on a device change, one password unlock turns Face ID or Touch
  ID back on, without a trip to Settings.

## [0.25.0] - 2026-10-20

### Added

- Image and PDF previews open at the content's size, scaled to fit the screen, in a resizable
  sheet on the Mac. They zoom with pinch, double-click or double-tap, and Zoom In, Zoom Out,
  Zoom to Fit and Actual Size buttons (⌘=, ⌘-, ⌘9 and ⌘0 on the Mac).

## [0.24.0] - 2026-10-20

### Added

- The entry editor asks before Save deletes attachments, or extra fields that had a value, for
  good. Removing an empty field or reordering saves without asking.

## [0.23.10] - 2026-10-19

### Fixed

- A group's icon in the entry list could be drawn cut off now and then.

## [0.23.9] - 2026-10-19

### Fixed

- `task cloudkit:validate` now checks the schema file matches Development, not only that it is
  valid, and the file now matches Development's indexes.

## [0.23.8] - 2026-10-19

### Fixed

- Attachments can now be removed while editing an entry; the removal takes effect when you save.
- On the Mac, the drag handle now sits at the right-hand edge of every row.

## [0.23.7] - 2026-10-19

### Added

- The CloudKit schema is kept in the repository, with tasks to export, check and deploy it, so
  TestFlight and App Store builds can sync once it's deployed to Production.

## [0.23.6] - 2026-10-19

### Security

- New automated tests feed random, truncated and damaged data to everything that reads untrusted
  input (encrypted records, Acrylic Wallet files) and check that tampered attachments, keys,
  logs and newer formats are refused. No change to the app's behaviour.

## [0.23.5] - 2026-10-19

### Fixed

- Importing from Acrylic Wallet refuses files over 512 MB before reading them, and rejects files
  whose structure has been tampered with to make the import slow. Attachments over 100 MB are
  left out, and the summary says how many.

## [0.23.4] - 2026-10-19

### Fixed

- A damaged or tampered copy of an item arriving from iCloud can no longer replace a good copy
  on an unlocked device, and a copy with a changed date can't win conflicts.
- A tampered vault record from iCloud can no longer make every unlock hang: the password-hashing
  settings are capped at 1 GB and 20 passes.
- Deleting the vault on another device now also removes this device's Face ID or Touch ID key,
  previews and copied values.
- On the Mac, a copied password is cleared from the clipboard when you quit.

## [0.23.3] - 2026-10-19

### Fixed

- On iPhone and iPad, the vault's database now has stronger file protection: it can't be read
  while the device is locked, though sync can keep writing to it. If iCloud wakes the app before
  you've unlocked the device, the vault opens once you do.

## [0.23.2] - 2026-10-19

### Fixed

- Items in Recently Deleted are now deleted for good only when you unlock, never straight after
  a sync, and only once this device has shown them for at least a week. An old copy coming back
  through iCloud, or a device whose clock is wrong, can no longer delete things at once.

## [0.23.1] - 2026-10-19

### Fixed

- Face ID and Touch ID can no longer be brought back after a restart, or after the re-entry
  period, by changing the date. The stored key is deleted once the period ends, and your next
  password unlock stores it again. After this update, unlock with your password once before Face
  ID or Touch ID is offered.

## [0.23.0] - 2026-10-19

### Changed

- On iPad, Settings, Lock, Help and iCloud Sync are at the top right of the screen instead of
  being folded into a ••• menu at the top of the sidebar, and New Group shows in the sidebar.
  On iPhone they stay above the groups list, now with a Help button.

## [0.22.0] - 2026-10-19

### Added

- On the Mac, Return adds a new line in Long Text fields and in the notes, as it does on iPhone
  and iPad. Option-Return still works too.

## [0.21.3] - 2026-10-19

### Changed

- The edit sheets are wider: at least 680 points on the Mac, and page-sized on iPad.
- Long field labels and values wrap and grow while editing instead of being cut off or
  scrolling on one line. Long Text values sit under their label at full width, and notes grow
  without a limit.
- On the Mac, the other rows slide out of the way as you drag a field or attachment.

## [0.21.2] - 2026-10-19

### Fixed

- On the Mac, drag to reorder in the editors now works. Each row has a handle in its own column
  on the right; drag it onto another row to put it there.

## [0.21.1] - 2026-10-19

### Fixed

- Save a Copy… no longer logs a warning that the attachment's file type can't be used for the
  save panel. The saved file keeps its name and extension.

## [0.21.0] - 2026-10-19

### Added

- Recently Deleted. Deleting an entry or a group moves it to Recently Deleted, at the bottom of
  the sidebar, instead of deleting it straight away. From there you can recover it, delete it
  for good, or delete everything at once. Anything left there is deleted for good after 30
  days. A deleted group takes its entries with it and brings them back when you recover it.

## [0.20.0] - 2026-10-19

### Added

- Drag to reorder while editing: a group's fields, an entry's extra fields, and its
  attachments, which the entry editor now lists for this. The new order is kept when you save.

### Fixed

- On iPad, the group editor's icon picker no longer takes up most of the screen and hides the
  group's fields.

## [0.19.1] - 2026-10-19

### Fixed

- On the Mac, Save a Copy… on an attachment now saves the file where you choose.

## [0.19.0] - 2026-10-19

### Added

- Show a field's values in a monospaced font, which makes card numbers, licence keys and
  codes easier to check. Turn it on per field in the group editor, or in an extra field's
  menu; labels keep the normal font. Passwords and concealed fields start monospaced, as
  before.

## [0.18.2] - 2026-10-19

### Fixed

- On iPad, opening an attachment no longer closes it again straight away.

## [0.18.1] - 2026-10-19

### Changed

- The project is ready to be published as open source: a contributing guide, an up-to-date
  README, and a website for the support page and privacy policy.

## [0.18.0] - 2026-10-19

### Added

- Help inside the app: short topics on getting started, your master password, locking,
  iCloud sync, attachments, moving from Acrylic Wallet and how your data is protected. On a
  Mac, choose Help ▸ Silicon Wallet Help; on iPhone and iPad, it's in Settings.
- About now links to the support page, the privacy policy and the source code.

## [0.17.1] - 2026-10-19

### Fixed

- Importing from Acrylic Wallet copes with more files: it no longer assumes one page size,
  accepts an accented password however it was typed, and says clearly when a file isn't a
  Wallet vault or uses a format it can't read yet.
- After an import, Silicon Wallet now explains why old Wallet files, Dropbox copies and
  exports should be deleted.

## [0.17.0] - 2026-10-19

### Added

- The lock screen has a new background: a softly blurred circuit board in Silicon Wallet's
  colours, with the password on a frosted card.

## [0.16.3] - 2026-10-19

### Changed

- The Touch ID symbol on the Mac lock screen is smaller.

## [0.16.2] - 2026-10-19

### Fixed

- If Face ID or Touch ID doesn't recognise you, Silicon Wallet now simply waits for your
  password (or another try) instead of showing an error. After too many failed attempts it
  explains that the password is needed.

## [0.16.1] - 2026-10-19

### Fixed

- On iPhone and iPad, Face ID and Touch ID no longer fail with an unhelpful error when the app
  is opened or brought back to the front. If something does go wrong, the message now says what.

## [0.16.0] - 2026-10-19

### Added

- A card view. Choose "as Cards" in the View Options menu, or press ⌘2 on the Mac, and your
  entries appear as cards across the window. Open a card to see the entry in a sheet, where you
  can copy, reveal or edit it. "as List" (⌘1) goes back to the list.

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
