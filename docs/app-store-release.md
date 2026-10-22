# Road to the App Store

How Silicon Wallet gets from the first commit to a free, universal app on the iOS and Mac
App Stores. Each item becomes an issue or PR when its turn comes. The steps follow the build
order in [DESIGN.md](../DESIGN.md) §8, with release work threaded in early so nothing blocks at
the end.

Decisions already made: the repo went public after the pre-beta security pass (B4, done
2026-10-20), and the App Store primary language is English (UK). Release 1.0 is tracked in
issue #101. There is no TestFlight testing phase (decided 2026-10-22): builds still upload to
App Store Connect, but Production sync is checked with a local Release build (B5) and 1.0 is
submitted directly, with manual release.


Each item below becomes an issue or PR when its turn comes. The steps are DESIGN.md §8's build order, with release work threaded in early so that nothing blocks at the end.

## B0. Apple accounts and identifiers (owner actions, start now and in parallel)
1. **Reserve the name** (done 2026-10-18). The App Store Connect record *Silicon Wallet*:
   - Apple ID **6824181307**;
   - platforms iOS and macOS, one record, so the purchase is universal;
   - primary language English (U.K.);
   - bundle ID `com.datoos.silicon-wallet`, SKU `silicon-wallet`.

   The name was free. Keep "Silicon Vault" or "Silicon Keyring" as fallbacks in case App
   Review objects to it (DESIGN.md §10). App Store Connect blocks new apps whenever an
   updated Apple Developer Program License Agreement is waiting for the Account Holder.
2. **Developer portal setup** (done 2026-10-18, team QKAYS6D525):
   - Xcode is signed in (Settings → Accounts) with the team's Apple ID.
   - App ID "Silicon Wallet", `com.datoos.silicon-wallet` (explicit), with iCloud (CloudKit)
     and Push Notifications. CloudKit pushes need no APNs certificate.
   - iCloud container `iCloud.com.datoos.silicon-wallet`, assigned to that App ID only.
     Containers can't be deleted, so don't create spares.
3. **App Store Connect API key** (done 2026-10-22, key "Silicon Wallet release"; the `.p8` is in
   `~/.appstoreconnect/private_keys/`):
   - Users and Access ▸ Integrations ▸ App Store Connect API: make a team key with the **Admin**
     role. The headless CI runner has no signing certificate, so Xcode uses cloud-managed
     distribution signing, which needs Admin (or App Manager plus "Access to Cloud Managed
     Distribution Certificate").
   - Add it to GitHub as the Actions secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (the
     `.p8` file's contents). For local uploads, set `ASC_KEY_PATH`, `ASC_KEY_ID` and
     `ASC_ISSUER_ID`, or leave them unset to use the Xcode account.
4. **Agreements and settings:**
   - Apple Developer Program License Agreement accepted 2026-10-18, and the App Store Connect
     agreements reviewed the same day.
   - **EU Digital Services Act** trader declaration submitted 2026-10-18 (in review then).
   - Still to do: set availability to all territories at a price of Free.
5. **Check the Mac mini runner** has Xcode 27 or later and the iOS 26 simulator runtime. If not, CI falls back to hosted `macos-26`.

## B1. Build steps 1 to 3: SiliconWalletKit (crypto, vault, store)
- These follow DESIGN.md §8 exactly, with tests for wrong passwords, tampered ciphertext and known-answer vectors.
- Add the swift-sodium dependency with an ADR. Pin it to an exact version and check its licence (ISC, compatible).
- **Release hooks inside these steps:**
  - Keep the threat model in DESIGN.md §5–7 (SECURITY.md points there).
  - Add the required-reason API entries for `UserDefaults` and file timestamps to `PrivacyInfo.xcprivacy` as soon as either is used.
  - Never log secrets, and add a test that checks it.

## B2. Build steps 4 and 5: UI and lock UX → **internal TestFlight starts here**
- **Release pipeline** (done, v0.13.0): `task release:archive`, `release:upload` and `release` in `Taskfile.yml`, `Config/ExportOptions.plist`, Release entitlements with production pushes, and `.github/workflows/release.yml`, which skips with a notice until the key secrets exist. As designed:
  - **Trigger:** the `vX.Y.Z` tag that `tag.yml` pushes, using the App token so the tag can start workflows. There is also a manual `workflow_dispatch`.
  - **Mac job:** two steps per platform (iOS, macOS):
    - archive: `xcodebuild archive -scheme SiliconWallet -destination 'generic/platform=iOS'` (and `generic/platform=macOS`), with `-allowProvisioningUpdates` and the App Store Connect API key flags;
    - upload: `xcodebuild -exportArchive` with an `ExportOptions.plist` set to `method: app-store-connect, destination: upload`.
  - **Versions:** `MARKETING_VERSION` comes from `VERSION`, and `CURRENT_PROJECT_VERSION` is `github.run_number`, which is unique and only goes up.
  - **Entitlements:** Release builds use `aps-environment: production`.
  - **Local tasks:** `task release:archive PLATFORM=ios|macos` and `task release:upload`.
- **TestFlight internal testing:** skipped (see the decisions above). Uploaded builds still show in TestFlight if it's ever wanted.
- **Accessibility from the start:** VoiceOver labels, Dynamic Type, keyboard navigation on Mac, and Reduce Motion.

## B3. Build steps 6 and 7: CloudKit sync and attachments
- **The schema gotcha.** TestFlight and App Store builds use CloudKit's **Production** environment. Record types created in Development don't exist there until deployed.
  - The schema is in the repo as `CloudKit/schema.ckdb` (issue #78): `VaultMeta`, `Group` and `Entry` with an encrypted `payload`, `modified` and `schemaVersion`/`formatVersion`; `Attachment` with `file` and `size`. It is exported from Development, so it carries the indexes CloudKit added there (queryable and sortable `modified`, `schemaVersion`, `formatVersion` and `size`). `CKSyncEngine` fetches by zone and never queries, so they go unused; they only index metadata that is already unencrypted.
  - `task cloudkit:export`, `cloudkit:validate` and `cloudkit:deploy` use `xcrun cktool` and a CloudKit management token saved in the keychain (`xcrun cktool save-token --type management`, owner action). `cloudkit:validate` checks the file and that it matches Development; `cloudkit:deploy` runs it, then opens CloudKit Console for "Deploy Schema Changes…".
  - Deploy to Production before any TestFlight build that syncs.
  - Production schema changes can only add, never remove or rename. Version the payload instead: `schemaVersion` is already in DESIGN.md.
- **Test matrix:** two devices on one Apple ID; signed-out iCloud; iCloud Drive off; full iCloud storage; account switching; zone deletion. The app must stay usable without iCloud, because App Review will test that.

## B4. Pre-beta security pass, then make the repo public
Done in the repo (issue #52, 2026-10-19):
- `gitleaks` over the full history: no leaks in 51 commits. No personal infrastructure names
  in tracked files or history. Commit author emails become public with the history.
- Dependency licences: swift-sodium and the libsodium it bundles are ISC, which is compatible
  with MIT. CommonCrypto and `libsqlite3` are system libraries.
- The shared workflows are vendored into `.github/workflows/` (ADR-0007).
- `pages.yml` publishes `site/` to GitHub Pages.
- `CONTRIBUTING.md` added; the README is up to date and asks forks to change the name and icon.
- A stray Claude session log in `Fixtures/AcrylicWallet/` was deleted before it was committed.

Still open:
- Review DESIGN.md §5–7 against the code, and run `/security-review` on the crypto, vault and
  import code.
- Known-answer vectors exist for Argon2id (CryptoTests). Seeded fuzz tests cover sealed values,
  Acrylic headers, files and pages, and the property-list text parser (FuzzTests, issue #77);
  TamperTests cover attachments, the key check, the wrapped key, newer formats and the access log.
- If possible, get an independent review of the crypto design. It is a password manager, and
  reviewers and users will ask.

**The flip** (done 2026-10-20 with `gh`, in this order):
1. Remove the `mac-mini` and `docker-linux` self-hosted runners from this repo (Settings ▸
   Actions ▸ Runners, and the runner configs on the Mac mini), and delete the repo variables
   `MAC_RUNNER` and `LINUX_RUNNER`, so every workflow falls back to GitHub-hosted runners
   (ADR-0007). Do this first: a fork can target any runner the repo has.
2. `gh repo edit adatoo/silicon-wallet --visibility public --accept-visibility-change-consequences`.
3. Settings ▸ Actions ▸ General: "Require approval for all external contributors" for fork
   pull request workflows.
4. Settings ▸ Code security: turn on private vulnerability reporting (SECURITY.md relies on
   it), secret scanning and push protection.
5. Settings ▸ Pages ▸ Source: "GitHub Actions"; then `gh workflow run pages` and check that
   `https://adatoo.github.io/silicon-wallet/support.html` and `privacy.html` load.
6. Open a test PR and confirm CI passes on hosted runners (`macos-26` must have an Xcode that
   builds the iOS 26 / macOS 26 targets). The first was #104's PR.

On the Mac mini, the Linux runner container is stopped; the Mac runner's LaunchDaemon
(`com.github.actions-runner.adatoo-silicon-wallet`) is booted out by the owner.

## B5. Build step 8: settings, polish and App Store assets → **external TestFlight**
- **App icon:** done (v0.8.0): an original chip-and-keyhole design drawn by `scripts/make-icon.swift` (`task icon`), with light, dark and tinted iOS variants and the full macOS set. Optionally redo it later as a layered `.icon` in Icon Composer for Liquid Glass.
- **Screenshots** (done, v0.12.0): `task screenshots` captures the iPhone and iPad sets from the simulators with the fake demo vault; Mac ones are taken by hand (AppStore/README.md). Sizes:
  - iPhone 6.9″ at 1320×2868 (required);
  - iPad 13″ at 2064×2752 (required, because the app runs on iPad);
  - Mac at 2880×1800 (16:10).

  Show 3 to 6 per platform: groups, entries, detail, generator, lock screen, sync.
- **Listing metadata in English (UK)** (done, v0.12.0), kept in the repo under `AppStore/metadata/en-GB/`, with review notes and the App Store Connect answers in `AppStore/`:
  - **Name:** Silicon Wallet. **Subtitle**, for example "Private, encrypted secrets".
  - **Promotional text**, a **description** and **keywords** (100 characters).
  - **Category:** Productivity, with Utilities as secondary.
  - **Copyright:** "© 2026 Arif Datoo".
- **URLs** (pages written, v0.12.0; publishing them is an owner action): a support URL and a **privacy policy URL**, both required. `site/` holds them; the metadata points at `https://adatoo.github.io/silicon-wallet/`, which works once GitHub Pages serves `site/` (Pages on a private repo needs a paid plan, so either enable it then or host `site/` elsewhere and update the two URL files). It covers:
  - the privacy policy: no data collected; iCloud data is end-to-end encrypted with a key Apple doesn't hold;
  - support and FAQ;
  - a link to the source.
- **App Privacy:** "Data Not Collected", matching `PrivacyInfo.xcprivacy`.
- **Age rating questionnaire:** all "None", which gives the lowest rating.
- **Accessibility Nutrition Labels:** declare only the features verified on each platform.
- **Export compliance** (done 2026-10-22): answered "None of the algorithms mentioned above", since every cipher comes from Apple's OS, and `ITSAppUsesNonExemptEncryption` is `NO` (AppStore/README.md).
- **Production smoke test, instead of TestFlight** (passed 2026-10-22 on the Mac and an iPhone): Release builds sync to CloudKit Production
  (`icloud-container-environment` in the Release entitlements). Back up the vault folder, then run
  a team-signed Release build on the Mac (`-configuration Release -allowProvisioningUpdates`) and
  on an iPhone or iPad (Xcode scheme ▸ Run ▸ Build Configuration: Release). Check the vault uploads,
  a second device receives it, Face ID / Touch ID work and an attachment round-trips.

## B6. Submission
- **App Review readiness checklist:**
  - **4.1 (copycats) and 5.2.5 (Apple trademarks):** the name and icon must not suggest Apple Wallet or Acrylic. Prepare a sentence explaining the name: "Silicon" refers to Apple silicon and the product is a secrets vault. Keep the fallback name ready.
  - **2.1 (completeness):** no placeholder UI. Import/export stays hidden until it ships.
  - **5.1.1 (privacy):** no account means account deletion doesn't apply. The privacy policy matches the app's behaviour.
  - **2.5.x:** only public APIs, the background mode used only for CloudKit pushes, and the sandbox justified.
- Marketing version **1.0.0**, made by a major bump PR that updates `VERSION` and the CHANGELOG (done 2026-10-22).
- Choose the build for iOS and for macOS in App Store Connect and submit both platforms together.
- **Release settings:**
  - manual release after approval;
  - **phased release** on iOS;
  - "Keep all attachments offline" and similar defaults reviewed.

## B7. Launch and after
- Release, then watch crash reports in Xcode Organizer. These are Apple-collected and opt-in, which is compatible with "Data Not Collected".
- Watch App Store reviews.
- **Every later release** follows one cycle:
  1. A PR, with its version bump, is merged.
  2. The merge is tagged.
  3. The release workflow uploads the build to App Store Connect.
  4. The build is chosen for a new version and submitted for review in App Store Connect.
- Phase 2 and 3 work, starting only when you ask: Acrylic import, export, AutoFill extension.

## Milestone summary
| Milestone | Gate |
|---|---|
| M0 Setup | `task ci` green locally and in CI; repo private; ruleset applied |
| M1 Kit (steps 1–3) | crypto, vault and store tests green, including tampered and wrong-password cases |
| M2 Upload pipeline (steps 4–5) | release workflow uploads both platforms |
| M3 Sync (steps 6–7) | Production schema deployed; two-device sync passes |
| M4 Public repo and Production smoke test | security pass done; listing, privacy policy and screenshots ready; local Release build syncs to Production |
| M5 1.0 on both App Stores | App Review approved; phased release on |
