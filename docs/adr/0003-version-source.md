# ADR-0003: `VERSION` is the version source; CI sets build numbers

- **Status:** Accepted (2026-10-15)

## Context

Every PR bumps the SemVer version, and the shared `version-bump` workflow reads a version file.
Xcode needs `MARKETING_VERSION` (the App Store's `CFBundleShortVersionString`) and a build
number (`CFBundleVersion`) that rises with every upload to App Store Connect.

## Decision

- `VERSION` holds the SemVer version and is the single version source.
- `task version:sync` writes it into `Config/Version.xcconfig` as `MARKETING_VERSION`, and
  `task version:check` (a hook and part of `task lint`) fails when they differ. The release
  commit changes `VERSION`, `Config/Version.xcconfig` and `CHANGELOG.md` together.
- `CURRENT_PROJECT_VERSION` stays `1` in the repo. The release workflow overrides it with the
  GitHub Actions run number for each upload.

## Consequences

- Version bumps never touch the generated project.
- Build numbers are unique and increasing without being committed.
