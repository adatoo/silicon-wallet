# Notes for App Review

Paste into App Store Connect → App Review Information → Notes.

---

Silicon Wallet is a password manager. It needs no account or sign-in.

To try it:
1. On first launch, choose any master password (at least 8 characters) and tap Create Vault.
   "Unlock with Face ID" is on by default and can be turned off on the same screen.
   The vault starts with example groups (Logins, Credit Cards and so on).
2. Tap + to add an entry. Concealed fields (such as passwords) are hidden until revealed.
3. Lock with the padlock button. To unlock, use Face ID or Touch ID, or tap "Use Password"
   and enter the same master password.

iCloud sync is optional and automatic when the device is signed in to iCloud; the app works
fully without it. Everything is encrypted on the device before it is stored or synced
(AES-256-GCM, with the key derived from the master password using Argon2id), so no
plaintext ever reaches CloudKit.

Export and import (File menu on the Mac; Settings on iPhone and iPad) need the master password.
An encrypted backup is protected by a separate export password chosen at the time; JSON is
plaintext and the app warns before saving it. Importing adds only items that aren't already in
the vault, so importing the same file twice changes nothing.

After five wrong master passwords in a row, the lock screen asks you to wait a minute before the
next try (doubling up to an hour); the countdown is shown. Face ID and Touch ID still unlock.

"Import from Acrylic Wallet" reads a vault file from Acrylic Software's discontinued Wallet
app, if the person has one. It isn't needed to use the app.

The app collects no data, has no analytics, and makes no network requests other than
CloudKit sync.

The name: "Silicon" refers to Apple silicon; the app is a secrets vault and is not affiliated
with Apple Wallet or Acrylic Software.
