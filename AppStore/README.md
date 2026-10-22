# App Store listing

Everything App Store Connect asks for apart from builds (docs/app-store-release.md, B5).

- `metadata/en-GB/`: the listing text, one file per field, ready to paste or upload. Limits:
  name and subtitle 30 characters, keywords 100, promotional text 170, description 4,000.
  Keywords must not name other apps (so not "Acrylic"); the description may mention importing.
- `review-notes.md`: the App Review notes.
- `screenshots/`: made by `task screenshots` (iPhone 6.3″ 1206×2622, which App Store Connect now
  requires, iPhone 6.9″ 1320×2868 and iPad 13″ 2064×2752),
  not committed. Mac screenshots (2880×1800) are taken by hand from `task dev` with the demo
  vault: run the built app with `-InMemoryVault -DemoVault`.

## Answers for App Store Connect

| Question | Answer |
|---|---|
| Category | Productivity; secondary Utilities |
| Price | Free, all territories |
| App Privacy | Data Not Collected |
| Age rating | All "None" (4+) |
| Copyright | © 2026 Arif Datoo |
| Sign-in required for review | No |
| Content rights | No third-party content |
| Accessibility Nutrition Labels | Declare only what's been checked on each platform: VoiceOver, Larger Text, Dark Interface and Reduced Motion are supported by the standard controls used; check each before declaring |

## Export compliance

Answered by the owner on 2026-10-22 as "None of the algorithms mentioned above": the app
implements no encryption of its own. Every cipher comes from Apple's operating system, AES-256-GCM
through CryptoKit and CommonCrypto for reading Acrylic Wallet files. From libsodium it uses only
Argon2id, a password hash rather than a cipher. `project.yml` sets
`ITSAppUsesNonExemptEncryption` to `NO`, so builds skip the question. Revisit this if the app ever
calls a non-Apple cipher (for example from libsodium) or adds its own protocol.
