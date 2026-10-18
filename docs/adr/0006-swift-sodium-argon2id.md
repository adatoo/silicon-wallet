# ADR-0006: Argon2id from libsodium, through swift-sodium

- **Status:** Accepted (2026-10-18)

## Context

The master password has to be turned into the key-encryption key with a memory-hard KDF
(DESIGN.md §5). Apple's frameworks don't offer one: CryptoKit has HKDF only, and CommonCrypto's
PBKDF2 isn't memory-hard. Argon2id is the current recommendation (RFC 9106), and writing it
ourselves would break the rule against hand-rolled crypto primitives (AGENTS.md).

## Decision

- Use **libsodium's `crypto_pwhash`** with `crypto_pwhash_ALG_ARGON2ID13`. It comes from
  [swift-sodium](https://github.com/jedisct1/swift-sodium), **pinned exactly to 0.11.0**.
  - The pin is `exact:` in `Packages/SiliconWalletKit/Package.swift`.
  - Licence: ISC, compatible with the app's MIT licence (ADR-0002).
- The kit depends only on the package's `Clibsodium` product, which is libsodium's prebuilt
  xcframework, and calls `crypto_pwhash` directly. The Swift `Sodium` wrapper isn't used:
  calling the C function directly lets us zero the password and output buffers
  (`sodium_memzero`) and avoid extra copies.
- Every other primitive stays in CryptoKit: AES-256-GCM, random keys and nonces.
- The parameters are stored with each vault (`KDFParameters`): a random 16-byte salt,
  3 passes and 64 MiB to start with, to be tuned to about 0.5 s on the slowest supported
  device. libsodium always uses a parallelism of 1.
- The password is normalised to Unicode NFC before hashing. Then the same password always
  derives the same key, whether it was typed precomposed (`ä`) or decomposed (`a` plus a
  combining diaeresis). The Acrylic fixtures showed both forms exist in practice
  (`Fixtures/AcrylicWallet/README.md`, vault f).

## Consequences

- There is one third-party dependency, and it's in the security-critical path. Before bumping
  the pin, check the release notes and licence, and rerun the known-answer tests.
- Those tests (`CryptoTests.swift`) check libsodium against vectors made with a separate
  implementation, OpenSSL's `ARGON2ID` KDF. Before use, that was checked against the
  reference implementation's own vector. libsodium needs a 16-byte salt, so the reference
  vectors can't be used directly.
- Changing the algorithm or the NFC rule later would stop existing vaults from opening. Any
  change needs a new `KDFParameters.Algorithm` case, and the old one kept for reading.
