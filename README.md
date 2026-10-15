# Silicon Wallet

A free, open-source secrets manager for iPhone, iPad and Mac, built in Swift and SwiftUI.
Your vault is encrypted on your device and synced through your own iCloud account, end to end.

> Status: early development. Nothing to install yet.

## What it will do

- Groups with their own field templates, entries, notes and attachments, and search.
- A master password, plus Face ID or Touch ID, auto-lock and clipboard clearing.
- iCloud sync through CloudKit, encrypted before anything leaves the device.
- Import from Acrylic Software's *Wallet*, which it is designed to replace.

The design is in [DESIGN.md](DESIGN.md); the architecture is summarised in
[docs/architecture.md](docs/architecture.md).

## Building

Needs macOS 26 or later, Xcode 26 or later, and [Task](https://taskfile.dev).

```sh
brew install go-task xcodegen lefthook gitleaks actionlint
task setup     # git hooks and a tool check
task test      # package, macOS and iOS Simulator tests
task dev       # build and open the Mac app
```

Run `task` to see every command.

## Licence

[MIT](LICENSE). Security issues: see [SECURITY.md](SECURITY.md).
