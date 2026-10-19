# ADR-0005: Acrylic Wallet import reads `.wallet` files natively; no SEE licence needed

- **Status:** Accepted (2026-10-18; importer added the same day)

## Context

Issue #1 ran a time-boxed spike to choose Silicon Wallet's Acrylic Wallet import route
(DESIGN.md §9). Two tracks ran in parallel, against fake fixtures only
(`Fixtures/AcrylicWallet/`), made on a Mac that never held a real vault:

- **Track 1, Wallet's own exports.** Wallet 3.5 offers CSV, TSV and a `.wallet`-format
  "Wallet Database" export; it has no XML export, despite `exportXML:`/`importXML` strings in
  its binary. CSV/TSV drop the header row, group names, field labels, the favourite flag and
  attachments, and store passwords and card numbers in plain text
  (`Fixtures/AcrylicWallet/README.md`, `NOTES.md`). So neither is enough on its own.
- **Track 2, a clean-room reader for `.wallet` files.** A `.wallet` file is a SQLite database
  encrypted with the commercial SQLite Encryption Extension (SEE), which has no open-source
  edition. The original plan if this failed was to buy the $2,000 perpetual SEE licence
  (`sqlite.org/com/see.html`).

A third-party tool, `pascal-wegner/acrylic-wallet-decrypt`, was reviewed and tried as a
reference oracle. It loads Wallet.app's own SEE-enabled SQLite build via symbol lookup, which
only works against an unstripped binary; Wallet 3.5's App Store build has those symbols
stripped (`nm -m Wallet | grep sqlite3_key` returns nothing), so it failed on every fixture and
was abandoned without disassembling anything.

## Decision

Track 2 succeeded by black-box known-plaintext analysis, using only:

- SEE's own public documentation (`sqlite.org/see/doc/trunk/www/readme.wiki`), which lists its
  four cipher options (RC4, AES-128-OFB, AES-128-CCM, AES-256-OFB) and explains that bytes
  16–23 of page 1 are always plaintext;
- the fixtures' known plaintext at those bytes (`SQLite format 3\0`) and across differing
  passwords (`a`–`i`, §C2 of issue #1);
- a brute-force search of key-derivation × cipher × IV hypotheses against that known
  plaintext, run with the system `cryptography` Python library for speed, then confirmed in
  Swift with CommonCrypto.

The scheme, confirmed end-to-end with `PRAGMA integrity_check` against all nine fixtures and
their three exports:

- **Cipher:** AES-256 in OFB mode (SEE's `aes256ofb`, most likely via `sqlite3-see-cccrypt.c`,
  SEE's recommended macOS/iOS variant).
- **Key:** `"W7f@" + password`, UTF-8, repeated/truncated to exactly 32 bytes. This is SQLite's
  own `-key` rule (repeat short material, truncate long material); there is no hash and no
  per-file salt, which matches the fixtures: files sharing a password are byte-identical
  wherever their plaintext matches, and never otherwise (`Fixtures/AcrylicWallet/README.md`,
  "The header").
- **Per-page IV:** the 1-based page number as a little-endian `UInt32`, zero-padded to 16
  bytes. There is no nonce (reserved-bytes byte is `0x00`), which is why the key alone, plus
  page number, fully determines each page's ciphertext.
- Bytes 16–23 of page 1 are left as literal plaintext, as SEE's documentation says.

This is implemented in `SiliconWalletKit`'s `AcrylicImport` module
(`AcrylicWalletCipher`/`AcrylicWalletFile`/`AcrylicWalletReader`), using CommonCrypto (a system
library, not a new dependency) for AES-256-OFB and the system `libsqlite3` to open the
decrypted bytes read-only, in memory only, via `sqlite3_deserialize` (DESIGN.md §5: plaintext
is never written to disk). Unit tests run this against every fixture in
`Fixtures/AcrylicWallet/`.

**No SEE licence is needed.** The format is read natively, with no SEE source, no
disassembly and no Acrylic code (per issue #1's stop rule, which never had to trigger).

## Scope of this decision

`AcrylicWalletReader` reads the container (groups, entries, attachments) and the entries'
field *values*, which are stored as flat `"field-UUID" = "value";` text. `AcrylicImporter`
(added 2026-10-18, at the owner's request) maps it into Silicon Wallet's model:

- `defaultheaders`/`extraheaders` are `NSKeyedArchiver` arrays of `{Type, UUID, Title, Section,
  Content-Type}`, decoded with only Foundation's plist classes allowed. `Type` 1 is a web
  address, 2 a user name, 3 a password; `Content-Type` 1 marks a secure field. Labels naming a
  secret (PIN, security code, CVV, card or account number) are concealed too.
- Values match fields by UUID; any value without a definition becomes an extra field, so
  nothing is dropped. An entry's `files` column lists its attachments' UUIDs in the `files`
  table. Favourites (`star`) and Wallet's `datelastupdated` dates come across.
- `VaultSession.importItems` saves it all in one batch, sealing each attachment under its own
  new key. The app's import sheet reads the chosen file once into memory and never writes it.

## Consequences

- Importer v1 can read a `.wallet` file directly; it doesn't depend on Wallet.app still
  running, so it also works after Rosetta stops running Wallet (macOS 28, autumn 2027).
- Wallet's CSV/TSV exports remain useful only as a secondary, lossy path (or a sanity check),
  given what they drop.
- `CommonCrypto` and `libsqlite3` are now linked into `SiliconWalletKit` for this reader only.
  They are system libraries, not new third-party SPM dependencies, so AGENTS.md's dependency
  rule (ask before adding anything beyond libsodium/swift-sodium) doesn't apply; noted here for
  visibility anyway.
- The reader and importer are proven against the fake fixtures and, by the owner, against
  their real vault (imported in the app); the code only reads the file it's given.
- Only Wallet 3.5 for Mac has been seen. To cope with other versions' files (issue #48), the
  reader takes the page size from the plaintext header bytes 16–17 instead of assuming 1024,
  refuses files with reserved bytes per page (byte 20; an SEE nonce or MAC this IV scheme
  doesn't cover) as `unsupportedFormat`, and retries a wrong password in its NFC and NFD
  forms. Other SEE ciphers (RC4, AES-128) aren't attempted; such files report a wrong
  password or an unsupported format, and nothing is imported.
- The key is the password itself, with no KDF or salt, so a leaked `.wallet` file can be
  brute-forced offline cheaply. This is Wallet's weakness, and the source is public, so the
  importer tells users to delete old copies, Dropbox copies and exports once imported.
