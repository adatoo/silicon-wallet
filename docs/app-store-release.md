# Road to the App Store

How Silicon Wallet gets from the first commit to a free, universal app on the iOS and Mac
App Stores. Each item becomes an issue or PR when its turn comes. The steps follow the build
order in [DESIGN.md](../DESIGN.md) §8, with release work threaded in early so nothing blocks at
the end.

Decisions already made: the repo stays private until the pre-beta security pass (B4), and the
App Store primary language is English (UK).


Each item below becomes an issue or PR when its turn comes. The steps are DESIGN.md §8's build order, with release work threaded in early so that nothing blocks at the end.

## B0. Apple accounts and identifiers (owner actions, start now and in parallel)
1. **Reserve the name.** In App Store Connect, create the app record *Silicon Wallet*:
   - platforms iOS and macOS, one record, so the purchase is universal;
   - primary language English (UK);
   - bundle ID `com.datoos.silicon-wallet`, SKU `silicon-wallet`.

   This tests early whether the name is taken or rejected. Pick a fallback name now, for example "Silicon Vault" or "Silicon Keyring", per DESIGN.md §10.
   App Store Connect blocks new apps until the Account Holder accepts the updated Apple
   Developer Program License Agreement (seen 2026-10-18).
2. **Developer portal setup** (done 2026-10-18, team QKAYS6D525):
   - Xcode is signed in (Settings → Accounts) with the team's Apple ID.
   - App ID "Silicon Wallet", `com.datoos.silicon-wallet` (explicit), with iCloud (CloudKit)
     and Push Notifications. CloudKit pushes need no APNs certificate.
   - iCloud container `iCloud.com.datoos.silicon-wallet`, assigned to that App ID only.
     Containers can't be deleted, so don't create spares.
3. **App Store Connect API key** (App Manager role):
   - Store the `.p8` in the login keychain.
   - Add it to GitHub as the Actions secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8`. It is used for CI uploads and `-allowProvisioningUpdates`.
4. **Agreements and settings:**
   - Accept the Free Apps agreement.
   - Make the **EU Digital Services Act trader status** declaration. As a free, non-commercial individual, "non-trader" is likely; confirm.
   - Set availability to all territories at a price of Free.
5. **Check the Mac mini runner** has Xcode 27 or later and the iOS 26 simulator runtime. If not, CI falls back to hosted `macos-26`.

## B1. Build steps 1 to 3: SiliconWalletKit (crypto, vault, store)
- These follow DESIGN.md §8 exactly, with tests for wrong passwords, tampered ciphertext and known-answer vectors.
- Add the swift-sodium dependency with an ADR. Pin it to an exact version and check its licence (ISC, compatible).
- **Release hooks inside these steps:**
  - Keep the threat model in `docs/security.md`.
  - Add the required-reason API entries for `UserDefaults` and file timestamps to `PrivacyInfo.xcprivacy` as soon as either is used.
  - Never log secrets, and add a test that checks it.

## B2. Build steps 4 and 5: UI and lock UX → **internal TestFlight starts here**
- **Release pipeline**, as `taskfiles/release.yml` plus `.github/workflows/release.yml`:
  - **Trigger:** the `vX.Y.Z` tag that `tag.yml` pushes, using the App token so the tag can start workflows. There is also a manual `workflow_dispatch`.
  - **Mac job:** two steps per platform (iOS, macOS):
    - archive: `xcodebuild archive -scheme SiliconWallet -destination 'generic/platform=iOS'` (and `generic/platform=macOS`), with `-allowProvisioningUpdates` and the App Store Connect API key flags;
    - upload: `xcodebuild -exportArchive` with an `ExportOptions.plist` set to `method: app-store-connect, destination: upload`.
  - **Versions:** `MARKETING_VERSION` comes from `VERSION`, and `CURRENT_PROJECT_VERSION` is `github.run_number`, which is unique and only goes up.
  - **Entitlements:** Release builds use `aps-environment: production`.
  - **Local tasks:** `task release:archive PLATFORM=ios|macos` and `task release:upload`.
- **TestFlight internal testing** on your own iPhone, iPad and Mac. It needs no review. Use it from step 4 onwards.
- **Accessibility from the start:** VoiceOver labels, Dynamic Type, keyboard navigation on Mac, and Reduce Motion.

## B3. Build steps 6 and 7: CloudKit sync and attachments
- **The schema gotcha.** TestFlight and App Store builds use CloudKit's **Production** environment. Record types created in Development don't exist there until deployed.
  - Keep the schema in the repo as `CloudKit/schema.ckdb`.
  - Add `task cloudkit:export`, `cloudkit:validate` and `cloudkit:deploy`, which use `xcrun cktool` and a CloudKit management token in the keychain.
  - Deploy to Production before any TestFlight build that syncs.
  - Production schema changes can only add, never remove or rename. Version the payload instead: `schemaVersion` is already in DESIGN.md.
- **Test matrix:** two devices on one Apple ID; signed-out iCloud; iCloud Drive off; full iCloud storage; account switching; zone deletion. The app must stay usable without iCloud, because App Review will test that.

## B4. Pre-beta security pass, then make the repo public
- Review `docs/security.md` against the code.
- Run `/security-review` and a dependency licence check.
- Test vectors are committed and fuzz tests run on decrypt and parse.
- Run `gitleaks` over the full history.
- If possible, get an independent review of the crypto design. It is a password manager, and reviewers and users will ask.
- Flip the repo to public. A public repo can't call reusable workflows in the private `engineering-standards` repo, so make those workflows reachable or vendor them first, as Quail does.
- Add `CONTRIBUTING.md`, and enable private vulnerability reporting.

## B5. Build step 8: settings, polish and App Store assets → **external TestFlight**
- **App icon:** an original `.icon` from Icon Composer, with Liquid Glass light, dark and tinted variants for iOS 26 and macOS 26, and nothing resembling Acrylic or Apple Wallet.
- **Screenshots**, automated through UI tests with obviously fake vault data, as `task screenshots`:
  - iPhone 6.9″ at 1320×2868 (required);
  - iPad 13″ at 2064×2752 (required, because the app runs on iPad);
  - Mac at 2880×1800 (16:10).

  Show 3 to 6 per platform: groups, entries, detail, generator, lock screen, sync.
- **Listing metadata in English (UK)**, kept in the repo under `AppStore/metadata/`:
  - **Name:** Silicon Wallet. **Subtitle**, for example "Private, encrypted secrets".
  - **Promotional text**, a **description** and **keywords** (100 characters).
  - **Category:** Productivity, with Utilities as secondary.
  - **Copyright:** "© 2026 Arif Datoo".
- **URLs:** a support URL and a **privacy policy URL**, both required. Host a small GitHub Pages site from `site/`, covering:
  - the privacy policy: no data collected; iCloud data is end-to-end encrypted with a key Apple doesn't hold;
  - support and FAQ;
  - a link to the source.
- **App Privacy:** "Data Not Collected", matching `PrivacyInfo.xcprivacy`.
- **Age rating questionnaire:** all "None", which gives the lowest rating.
- **Accessibility Nutrition Labels:** declare only the features verified on each platform.
- **Export compliance.** The app uses encryption, through CryptoKit and libsodium's Argon2id. Answer the App Store Connect questionnaire, then set `ITSAppUsesNonExemptEncryption` to match, so each build skips the prompt.
  - **To verify:** before submission, check the current US export rules (BIS mass-market and open-source publication) and the France declaration requirement against what App Store Connect asks at that time. I'm not certain of the current specifics.
- **External TestFlight:** this needs Beta App Review. Use a public link, and write review notes that explain:
  - the app needs no account;
  - you create a vault with any master password;
  - iCloud sync is optional.

## B6. Submission
- **App Review readiness checklist:**
  - **4.1 (copycats) and 5.2.5 (Apple trademarks):** the name and icon must not suggest Apple Wallet or Acrylic. Prepare a sentence explaining the name: "Silicon" refers to Apple silicon and the product is a secrets vault. Keep the fallback name ready.
  - **2.1 (completeness):** no placeholder UI. Import/export stays hidden until it ships.
  - **5.1.1 (privacy):** no account means account deletion doesn't apply. The privacy policy matches the app's behaviour.
  - **2.5.x:** only public APIs, the background mode used only for CloudKit pushes, and the sandbox justified.
- Pick a marketing version of **1.0.0**, made by a major bump PR that updates `VERSION` and the CHANGELOG.
- Choose the build for iOS and for macOS in App Store Connect and submit both platforms together.
- **Release settings:**
  - manual release after approval;
  - **phased release** on iOS;
  - "Keep all attachments offline" and similar defaults reviewed.

## B7. Launch and after
- Release, then watch crash reports in Xcode Organizer. These are Apple-collected and opt-in, which is compatible with "Data Not Collected".
- Watch TestFlight feedback and App Store reviews.
- **Every later release** follows one cycle:
  1. A PR, with its version bump, is merged.
  2. The merge is tagged.
  3. The release workflow uploads the build to TestFlight.
  4. The build is promoted manually in App Store Connect.
- Phase 2 and 3 work, starting only when you ask: Acrylic import, export, AutoFill extension.

## Milestone summary
| Milestone | Gate |
|---|---|
| M0 Setup | `task ci` green locally and in CI; repo private; ruleset applied |
| M1 Kit (steps 1–3) | crypto, vault and store tests green, including tampered and wrong-password cases |
| M2 Internal TestFlight (steps 4–5) | release workflow uploads both platforms |
| M3 Sync (steps 6–7) | Production schema deployed; two-device sync passes |
| M4 Public repo and external beta | security pass done; listing, privacy policy and screenshots ready |
| M5 1.0 on both App Stores | App Review approved; phased release on |
