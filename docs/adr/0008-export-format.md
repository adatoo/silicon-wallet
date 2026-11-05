# ADR-0008: Export as a password-protected backup or plaintext JSON, from one schema

- **Status:** Accepted (2026-11-05; related entries and the Apple Passwords marker added the
  same day)

## Context

A vault lives only in the app and in iCloud. People need a copy they control: to keep a backup
outside iCloud, to restore a vault, or to move to another app (DESIGN.md §9, issue #119). An
export leaves the vault's protection, so the format decides how safe that copy is.

## Decision

- **Two formats, one schema.** `ExportDocument` (`SiliconWalletKit/Export`) holds the groups
  and entries in use (not Recently Deleted), with their field templates, values, extra fields,
  notes, favourites, dates, attachments, related entries (`related`, the IDs an entry links
  to) and whether the password is kept in Apple Passwords (`inApplePasswords`). Both are left
  out when empty or false, so older files and readers are unaffected. It's separate from the
  model's own `Codable` form, so
  the file format doesn't change when the model does, and it never holds an attachment's file
  key. It's versioned (`format: "silicon-wallet-export"`, `version: 1`).
- **Silicon Wallet backup** (`.siliconwallet`, type `com.datoos.silicon-wallet.backup`):
  - Protected by an **export password chosen at export**, not the master password. A backup
    stays openable after the master password changes, and handing one over doesn't reveal it.
  - Key: Argon2id (ADR-0006) of the NFC-normalised export password, with fresh
    `KDFParameters.generate()` and so a random salt per file. Sealing: the vault's sealed-value
    format (DESIGN.md §5) with two new purposes, `export-manifest` and `export-attachment`.
  - Layout, big-endian:
    `"SWBACKUP" ‖ format (UInt16 = 1) ‖ header length (UInt32) ‖ header (JSON: the KDF
    parameters) ‖ sealed manifest length (UInt64) ‖ sealed manifest ‖ for each attachment:
    its ID (16 bytes) ‖ sealed length (UInt64) ‖ sealed contents`.
  - The manifest is the `ExportDocument` without attachment data, with each attachment's
    SHA-256; each attachment is sealed with its own ID as associated data. Only the KDF
    parameters are readable without the password. Changing them only changes the key, so
    it fails like a wrong password.
- **JSON** (`.json`): the same document, pretty-printed, with each attachment's contents inline
  as base64. **Not encrypted**: the app asks for the master password and warns before it's made,
  and the summary says to delete it.
- Both need the master password, and a saved export is recorded in the access log.
- **Import** reads both. Groups and entries are matched by ID: anything the vault already has,
  in use or in Recently Deleted, is left alone and the rest is added, so importing the same file
  twice adds nothing and nothing is ever overwritten. An entry goes into its own group: one from
  the file, one already here, or one brought back from Recently Deleted (alone, as recovering an
  entry does). Values for fields its group no longer has become extra fields, labelled from the
  file. Attachments are sealed under new file keys. Links to entries the vault won't have after
  the import are dropped.
- **Against a hostile file:** files over 1 GiB are refused before they're read; KDF parameters
  outside `KDFParameters.isWithinLimits` are refused before deriving a key; a newer format or
  schema version is refused; lengths are checked against the file; in a backup every listed
  attachment must be present and open, and no chunk may be unlisted or repeated; an attachment
  whose contents don't match its SHA-256 fails the import; attachments over 100 MB are left out
  and counted; repeated IDs keep their first use.

## Consequences

- The export is built in memory and handed to the save panel, and an import reads the whole file
  into memory, so nothing unencrypted is written anywhere but where the person saves it. A vault
  whose attachments run to gigabytes would need a streamed writer and reader; the backup layout,
  with attachments in separate chunks after the manifest, allows that without a format change.
- A backup is only as strong as its export password; the app asks for at least 8 characters and
  shows the strength meter. A JSON export has no protection at all.
- Other apps' formats and CSV are not supported.
