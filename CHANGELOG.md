# Changelog

All notable changes to Silicon Wallet are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
