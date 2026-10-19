# ADR-0007: Once public, CI runs on GitHub-hosted runners only; shared workflows are vendored

- **Status:** Accepted (2026-10-19)

## Context

The repo goes public after the pre-beta security pass (ADR-0002, docs/app-store-release.md
B4). Two things in its CI don't survive that:

- **Self-hosted runners.** While private, CI runs on the owner's Mac mini (`mac-mini`, a
  LaunchDaemon) and a Docker runner on the same machine (`docker-linux`), because GitHub-hosted
  runners are blocked by billing on private repos. In a public repo, anyone can open a pull
  request from a fork, and the workflow files in that PR are the ones that run. A fork can
  change `runs-on` to any label the repo has, so `if:` guards in our own YAML can't keep a
  stranger's code off the Mac mini. Requiring approval for outside contributors helps, but
  one careless approval would be enough.
- **Reusable workflows.** `version-bump`, `issue-link`, `auto-merge` and `tag-on-merge` are
  called from the private `adatoo/engineering-standards` repo. A public repo can't call
  workflows in a private one.

## Decision

- **GitHub-hosted runners only, from the flip onwards.** Standard hosted runners are free for
  public repos. The workflows already read `vars.LINUX_RUNNER || 'ubuntu-latest'` and
  `vars.MAC_RUNNER || 'macos-26'`, so at the flip the owner deletes those two repo variables
  and removes both self-hosted runners from the repo. With no self-hosted runner registered,
  a fork has nothing to target. Quail made the same choice.
- **Vendor the four shared workflows** into `.github/workflows/`, unchanged apart from a
  header comment naming the source version (v0.6.0), and call them as
  `./.github/workflows/<name>.yml`. To update one, copy the new version over it. This departs
  from the engineering standards' "reuse, don't copy" rule, which assumes private repos.
- `release.yml` runs only on version tags and manual dispatch, never on a pull request, and
  uses cloud-managed signing with the App Store Connect key, so it moves to hosted runners too.
- `merge.yml` uses `pull_request_target`, which runs the base branch's workflow with secrets.
  It's safe because the auto-merge job never checks out PR code and only runs for PRs opened
  by `adatoo`.

## Consequences

- Hosted macOS runners are slower than the Mac mini and may lag behind new Xcode releases.
  If a build needs a newer Xcode than the image's default, select it with `DEVELOPER_DIR`, as
  Quail does.
- Hosted macOS runners have a GUI session, so the app-hosted tests (`test:macos`) could move
  into CI later. For now `ci:mac` stays as it is.
- Until the flip, nothing changes: the variables still point at the self-hosted runners.
