#!/usr/bin/env bash
# Install the pinned CI tools (task, actionlint, gitleaks, shellcheck) on a
# Linux runner, hosted (x86_64) or the Mac mini's OrbStack runners (aarch64).
# Every archive is checked against a pinned SHA-256 before it is unpacked.
set -euo pipefail

dest="${1:-$HOME/.local/bin}"
mkdir -p "$dest"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

fetch() { # url sha256 file
  curl -fsSL --retry 3 -o "$tmp/$3" "$1"
  echo "$2  $tmp/$3" | sha256sum -c --quiet -
}

if [ "$arch" = amd64 ]; then
  fetch https://github.com/go-task/task/releases/download/v3.53.1/task_linux_amd64.tar.gz \
    a54a408f6861ff921f6e87774180db31bacd8c1e7c944ca696db9fea49a82fc7 task.tgz
  fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_amd64.tar.gz \
    8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 actionlint.tgz
  fetch https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz \
    551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb gitleaks.tgz
  fetch https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz \
    8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 shellcheck.txz
else
  fetch https://github.com/go-task/task/releases/download/v3.53.1/task_linux_arm64.tar.gz \
    e3ad19101493a0112e1f22ae8ccc54bf03e533b1076a0ca1e6c782a09ad2e588 task.tgz
  fetch https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz \
    325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 actionlint.tgz
  fetch https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_arm64.tar.gz \
    e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 gitleaks.tgz
  fetch https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.aarch64.tar.xz \
    12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588 shellcheck.txz
fi

tar -xzf "$tmp/task.tgz" -C "$dest" task
tar -xzf "$tmp/actionlint.tgz" -C "$dest" actionlint
tar -xzf "$tmp/gitleaks.tgz" -C "$dest" gitleaks
tar -xJf "$tmp/shellcheck.txz" -C "$tmp"
install -m 0755 "$tmp/shellcheck-v0.11.0/shellcheck" "$dest/shellcheck"

if [ -n "${GITHUB_PATH:-}" ]; then echo "$dest" >> "$GITHUB_PATH"; fi
"$dest/task" --version
