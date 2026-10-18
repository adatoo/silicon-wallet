# App Store listing

Everything App Store Connect asks for apart from builds (docs/app-store-release.md, B5).

- `metadata/en-GB/`: the listing text, one file per field, ready to paste or upload. Limits:
  name and subtitle 30 characters, keywords 100, promotional text 170, description 4,000.
  Keywords must not name other apps (so not "Acrylic"); the description may mention importing.
- `review-notes.md`: the App Review notes.
- `screenshots/`: made by `task screenshots` (iPhone 6.9″ 1320×2868 and iPad 13″ 2064×2752),
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

## Export compliance (owner decision)

The app encrypts the user's own data with standard algorithms: AES-256-GCM from Apple's
CryptoKit, and Argon2id (a password hash, not a cipher) from libsodium. It doesn't use
proprietary algorithms. App Store Connect's questionnaire asks whether the app uses encryption,
whether it's exempt, and about France. Answer it with your own judgement or advice, then set
`ITSAppUsesNonExemptEncryption` in `project.yml` to match so each build skips the question.
This repo doesn't make that legal call for you.
