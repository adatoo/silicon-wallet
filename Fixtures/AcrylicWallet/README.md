# Acrylic Wallet fixtures

Fake vaults made with Acrylic Wallet 3.5 on 2026-10-18, for the migration spike (issue #1).
**Everything here is fake**, passwords included. They were made in a fresh Wallet install, in
the owner's own account on a Mac that never held a real vault, with sync, browser AutoFill and
Touch ID unlock all off.

## Vaults

| File | Password | Contents |
|---|---|---|
| `a.wallet` | `fakepass` | Groups Fake Logins and Fake Accounts, each with 3 custom field labels; 5 entries, each with a note; Example Bank starred |
| `b.wallet` | `fakepass` | 5 entries, none shared with a |
| `c.wallet` | `fakepass1234` | 2 entries |
| `d.wallet` | `fakepass12XY` | 2 entries; the first 12 characters match c |
| `e.wallet` | `fakepass-fakepass-fakepass-fakepass-1234` | 2 entries; 40 characters |
| `f.wallet` | `fake-pässwörd-✓` | 2 entries with accented and non-Latin text; the password was pasted, so probably NFC |
| `g.wallet` | `fakepass` | 32 entries; Example Attachment Holder has `attachment-test.png` attached |
| `h.wallet` | `fakepass-2` | the same contents as a, re-entered by hand; created as `fakepass`, then changed |
| `i.wallet` | `fakepassword` | a Web Passwords entry with a fake password, and a Credit Cards entry with the test card `4111 1111 1111 1111` |

## Exports (File → Export)

Wallet 3.5 offers only Wallet Database, Tab Delimited Text and CSV. It has no XML export,
although its binary contains the strings `exportXML:` and `importXML`.

| File | Made from | Notes |
|---|---|---|
| `a.csv`, `a.tsv` | a | |
| `g.csv`, `g.tsv` | g | |
| `a-export.wallet` | a | password `fakepass` |
| `g-export.wallet` | g | password `fakepass` |
| `i.csv`, `i.tsv` | i | |
| `i-export.wallet` | i | password `fakepassword` |

What the text exports keep:
- They keep the title, the field values in order, and the note. Passwords and card numbers
  come out in plain text (see `i.csv`), so a real export must be treated as a secret.
- They lose the header row, field labels, group names, the favourite flag and attachments.
- Empty fields stay as `""`, and each row has as many columns as its group has fields, so
  a column's meaning comes only from the group's field order.
- There is no newline at the end of the file.

A database export is the same size as its source and differs in only a few bytes. Exporting
also re-saved the open vault.

## The header

Bytes 16 to 23 are plaintext in every file: `04 00 01 01 00 40 20 20`. That means 1024-byte
pages, a legacy journal and no reserved bytes.

Bytes 0 to 15 are identical in every file whose password is `fakepass` (a, b, g and both
exports), and differ for every other password, c and d included. So the first block is
`SQLite format 3\0` encrypted under a key that depends only on the password:
- there is no per-file salt;
- c and d differ, but only in their last two characters, so they don't show whether long
  passwords are truncated.

Comparing whole pages shows the same pattern. Files with the same password have matching
ciphertext wherever their contents match, down to single bytes, and files with different
passwords never match. So the encryption depends only on the password and the page, with
no per-file or per-write randomness.

## Caveats

- Only i holds a card number and a Web Passwords "password" field; the owner added those by
  hand. a to h leave them empty.
- While making c, its master password (`fakepass1234`) was typed into a note and deleted
  before saving. Traces may remain in a free page of `c.wallet`. That is harmless, because
  the password is fake.

`NOTES.md` is the log made while creating the vaults: the setup screens, the group editor
and the export menu.
