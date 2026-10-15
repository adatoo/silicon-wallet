# ADR-0004: Sync through `CKSyncEngine`, not SwiftData's CloudKit integration

- **Status:** Accepted (2026-10-15)

## Context

Vault records must be encrypted by the app before they leave the device, with only the record
ID, type, modified date, schema version and ciphertext length in the clear (DESIGN.md §5). The
records also need custom conflict handling (§7).

SwiftData's built-in CloudKit mirroring syncs model properties as they are, decides the record
layout itself, and gives no control over conflicts.

## Decision

- SwiftData is a local-only store of ciphertext envelopes.
- Sync uses `CKSyncEngine` against the private database, in a custom zone `Vault`.
- Payloads go in `CKRecord.encryptedValues`, so CloudKit's own encryption sits on top of ours.

## Consequences

- We write the record mapping, the conflict resolution and the persistence of sync state ourselves.
- The CloudKit schema must be deployed to Production before TestFlight builds can sync
  (docs/app-store-release.md, B3).
