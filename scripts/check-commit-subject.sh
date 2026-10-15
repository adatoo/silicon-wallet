#!/usr/bin/env bash
# commit-msg hook: the subject must follow AGENTS.md §"Commits and history".
set -euo pipefail
subject="$(head -n1 "$1")"
case "$subject" in
  "Merge "* | "Revert \""* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac
pattern='^(feat|fix|chore|docs|ci|refactor|test)(\([a-z0-9._/-]+\))?: [^ ].*[^.]$'
if ! printf '%s' "$subject" | grep -Eq "$pattern" || [ "${#subject}" -gt 72 ]; then
  echo "Commit subject must be '<type>(scope): summary' (feat, fix, chore, docs, ci, refactor or test)," >&2
  echo "at most 72 characters, with no trailing full stop. Got: $subject" >&2
  exit 1
fi
