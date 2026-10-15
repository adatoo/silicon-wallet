# ADR-0002: MIT licence

- **Status:** Accepted (2026-10-15)

## Context

The owner's engineering standards make personal repos proprietary by default. Silicon Wallet's
goals (DESIGN.md §1) are to be free and open source and to ship on the App Store. The GPL's
terms conflict with the App Store's.

## Decision

Silicon Wallet is MIT-licensed, © 2026 Arif Datoo. Dependencies must be MIT/BSD/ISC-compatible.
The repo stays private until the pre-beta security pass, then goes public
(docs/app-store-release.md, B4).

## Consequences

- Anyone can build and redistribute it, including on other stores.
- Closed or copyleft code can't be bundled. That rules out, for example, GPL importers and
  shipping source for a commercially licensed library.
