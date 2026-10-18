# Wallet 3.5 fixture notes (Silicon Wallet migration spike, issue #1)

All data in this folder is FAKE. Master/export passwords were typed by Arif, not by Claude.
Card numbers were deliberately not entered anywhere; Web Passwords "password" fields were left empty.

## Files
| File | Master password | Contents |
|---|---|---|
| a.wallet | fakepass | Groups "Fake Logins" (Login Email, Member Number, Support Phone) and "Fake Accounts" (Account Ref, Security Question, Renewal Date); 5 entries, all with notes; Example Bank starred |
| a.csv / a.tsv | - | CSV / tab-delimited export of a |
| a-export.wallet | fakepass | "Wallet Database" export of a |
| b.wallet | fakepass | 3 Web Passwords entries (user name + url only) + 2 Serial Numbers entries; no overlap with a |
| c.wallet | fakepass1234 | 1 Serial Numbers + 1 Web Passwords entry |
| d.wallet | fakepass12XY | 1 Serial Numbers + 1 Web Passwords entry |
| e.wallet | fakepass-fakepass-fakepass-fakepass-1234 (40 chars) | 1 Serial Numbers + 1 Web Passwords entry |
| f.wallet | fake-pässwörd-✓ | 2 entries with non-ASCII data (Übersetzer, Fäke Üser, Exämple GmbH, café, naïve, ✓, 日本) |
| g.wallet | fakepass | 32 Serial Numbers entries; "Example Attachment Holder" has attachment-test.png attached |
| g.csv / g.tsv | - | CSV / tab-delimited export of g |
| g-export.wallet | fakepass | "Wallet Database" export of g |
| h.wallet | fakepass-2 (created as fakepass, then changed) | Same groups/entries/notes/star as a (re-entered by hand, not copied) |
| i.wallet | fakepassword | Made by Arif: 1 Web Passwords entry "fake password" (user name + password) and 1 Credit Cards entry "fake card" (card number) |
| i.csv / i.tsv / i-export.wallet | - / - / fakepassword | Exports of i (export password typed by Arif) |
| attachment-test.png | - | 200x120 blue "FAKE TEST IMAGE" PNG used as g's attachment |

Originals were left in Wallet's container folder as Database.wallet.done-a ... done-h.

## Setup flow
- First launch with no Database.wallet shows "Wallet Setup": Welcome -> Create Password -> Enable AutoFill -> Complete Setup.
  Welcome offers "New Database" or "Sync Existing" (always chose New Database).
- Enable AutoFill page only offers "Install Extensions..." (skipped); Continue goes on without installing.
- Each new database gets default groups: Serial Numbers, Web Passwords, Credit Cards.
- Settings (Wallet > Settings…): Security has "Require password" (on), "Allow Touch ID unlock" (OFF throughout — no keychain),
  auto-lock on sleep (on). Sync tab: Dropbox Sync OFF throughout. AutoFill: "Enable Browser Extensions" OFF.
- File menu also offers "Sync with Device (Wi-Fi)…" and "Sync with iCloud" (greyed). Never used.
- Wallet always opens .../Containers/com.acrylic.WalletMac/Data/Library/Application Support/Wallet/Database.wallet;
  renaming it aside makes the next launch show setup again. No separate attachments file/folder appeared there (g's image seems embedded).

## Passwords
- 40-character password (e) accepted with no warning or truncation message.
- Non-ASCII password (f) accepted. It was PASTED, so ä/ö are most likely precomposed (NFC). A typed/decomposed (NFD)
  version would be different bytes — worth testing normalisation in the migration.
- Change password: Settings > Security > "Change Password..." sheet with Current / New / Verify and a strength meter; "Set" button.

## Groups and entries
- New Group sheet: name + icon menu, 3 default fields "Header 1/2/3" with a type popup (default Text), "Add Field",
  "Add Section", and an "Enable AutoFill" checkbox (left unchecked).
- Field labels are displayed lower-cased in the entry view ("Login Email" -> "login email"); long labels are truncated ("securit…uestion").
- Built-in group fields: Web Passwords = user name, password, url. Serial Numbers = serial number, name, organization | developer, download url (two sections).
- Favourite = Entry > "Star Entry" (⌘M); starred entries are listed under a "★" section header.
- Attach = Entry > "Attach File…" (⌘O) — a normal Open panel; the entry then shows the file with view/share buttons.
- Entry menu also has "Duplicate Entry" (⌘D).
- Cosmetic: the star/group icon is drawn over the entry title in the detail pane.

## Exports
- File > Export offers only "Wallet Database…", "Tab Delimited Text…", "CSV…". There is NO XML export in 3.5,
  so a.xml and g.xml could not be produced.
- Save sheet defaulted to ~/Documents (name "Wallet Database"); after choosing wallet-fixtures once it remembered it.
- CSV/TSV: no header row, no group name column, no favourite flag, no attachments, every value double-quoted,
  empty fields as "", rows sorted by group then title, NO trailing newline. Column count follows each group's fields
  (a.csv rows have 5 columns, g.csv rows 7). .tsv is the same with tabs (same byte size as .csv because , and TAB are both 1 byte).
- "Wallet Database…" export adds a required Password field to the save sheet (typed by Arif).
  The export is the same size as the live DB and differs from it in only 4 bytes (around offset 24);
  exporting also re-saved the live DB (a.wallet and a-export.wallet have mtimes 4 ms apart).
- Both .wallet files start with the same 24-byte header (d2 8b 36 de f7 7a a9 8c 55 06 ae ab 51 7b c8 aa 04 00 01 01 00 40 20 20),
  Later correction: those 16 bytes are the same only for files sharing a password (fakepass); c to f, h and i
  each differ. See README.md, "The header".

- **CSV/TSV exports contain secrets in PLAIN TEXT**: i.csv has the Web Passwords password and the full card number
  unencrypted (5 columns per row; card number kept with its spaces). Treat any real export as sensitive.
- Credit Cards / Web Passwords rows still have no header, so column meaning must come from the group's field order.

## Mishaps (fixed)
- c.wallet: vault password was briefly typed into an entry note and removed before saving; deleted text may still exist
  inside the encrypted file. One entry in c was briefly "untitled" before being renamed.
- Group sheet and entry editing needed the window on a normal (non-full-screen) desktop.
