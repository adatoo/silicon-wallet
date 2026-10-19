# Silicon Wallet

A free, open-source secrets manager for iPhone, iPad and Mac, built in Swift and SwiftUI.
Your vault is encrypted on your device and synced through your own iCloud account, end to end.

> Status: nearly ready for a free release on the App Store.

## What it does

- Groups with their own field templates, entries, notes and attachments, and search.
- A master password, plus Face ID or Touch ID, auto-lock and clipboard clearing.
- iCloud sync through CloudKit, encrypted before anything leaves the device.
- A password generator, an access log, and short help inside the app.
- Import from Acrylic Software's *Wallet*, which it is designed to replace.

No account, no analytics, no tracking. Support and the privacy policy are at
[adatoo.github.io/silicon-wallet](https://adatoo.github.io/silicon-wallet/).

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

Run `task` to see every command. To contribute, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

[MIT](LICENSE). Security issues: see [SECURITY.md](SECURITY.md).

### Name and icon

The code is yours to use under the MIT Licence, but the name "Silicon Wallet" and its icon
identify this project. If you publish a fork, please give it a different name and icon so
nobody mistakes it for this app.
