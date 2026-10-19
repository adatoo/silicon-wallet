# Contributing to Silicon Wallet

Thanks for helping. Silicon Wallet is a password manager, so changes are held to a high bar,
especially anything that touches encryption, storage or sync.

## Before you start

- **Security problems:** don't open a public issue. Use the private route in
  [SECURITY.md](SECURITY.md).
- **Bugs and ideas:** open an issue first, so we can agree the scope before you write code.
  Every pull request closes an issue (`Closes #N` in its description).
- Read [DESIGN.md](DESIGN.md). It holds every agreed decision; a change that departs from it
  updates it in the same pull request. Bigger decisions are recorded in [docs/adr](docs/adr).

## Building and testing

You need macOS 26 or later, Xcode 26 or later, and [Task](https://taskfile.dev):

```sh
brew install go-task xcodegen lefthook gitleaks actionlint
task setup     # git hooks and a tool check
task ci        # everything CI runs, plus the app-hosted tests
task dev       # build and open the Mac app (ad-hoc signed, no iCloud)
```

Run `task` to list every command. The Xcode project is generated: edit `project.yml` and run
`task generate`; never edit `SiliconWallet.xcodeproj` by hand.

## Rules that matter most

- All non-UI logic lives in the `SiliconWalletKit` package, with tests. Crypto and vault code
  needs tests for wrong passwords and tampered ciphertext.
- Never write plaintext vault data to disk, logs, caches, `UserDefaults` or iCloud.
- Use CryptoKit (and libsodium for Argon2id). Never hand-roll crypto.
- **Never use real secrets in tests or fixtures.** Use obviously fake data, and never attach a
  real vault or `.wallet` file to an issue.
- No new dependencies without discussing it in an issue first.
- Swift 6 language mode, SwiftUI; format with `task fmt`.

## Pull requests

- Branch names: `<type>/<short-description>`, such as `fix/sync-retry`.
- Commit subjects: `<type>(scope): <summary>`, where the type is one of `feat`, `fix`,
  `chore`, `docs`, `ci`, `refactor` or `test`. Imperative mood, British English, at most 72
  characters.
- The maintainer handles the version bump and changelog when merging, so you don't need to.
- Describe what changed, how you tested it, and any change in behaviour.

By contributing, you agree that your work is released under the [MIT Licence](LICENSE).
