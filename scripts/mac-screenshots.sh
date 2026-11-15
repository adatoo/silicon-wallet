#!/bin/bash
# Captures the Mac App Store screenshots (2880×1800) from the demo vault
# (-InMemoryVault -DemoVault), the same screens as scripts/screenshots.sh. Run through
# `task screenshots:mac`. The terminal app needs Screen Recording permission (System Settings ▸
# Privacy & Security ▸ Screen & System Audio Recording) to capture the window.
#   scripts/mac-screenshots.sh <app> <output dir>
set -euo pipefail

app="$1"
out="$2/Mac"
executable="$app/Contents/MacOS/SiliconWallet"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# name|launch arguments, separated by ";" so values can contain spaces
shots=(
  "1-home|-ScreenshotSidebar;Logins;-ScreenshotEntry;Example Mail"
  "2-card|-ScreenshotSidebar;favorites;-ScreenshotEntry;Example Visa"
  "3-related|-ScreenshotSidebar;Logins;-ScreenshotEntry;Example Bank Online"
  "4-bank|-ScreenshotSidebar;Bank Accounts;-ScreenshotEntry;Example Bank"
  "5-notes|-ScreenshotSidebar;Secure Notes;-ScreenshotEntry;Wi-Fi at Home"
)
# No lock screen: on the Mac, AutoFill draws its Passwords… button over the window's title bar.

mkdir -p "$out"
for shot in "${shots[@]}"; do
  name="${shot%%|*}"
  IFS=";" read -r -a arguments <<< "${shot#*|}"
  # -n starts a separate copy even when the installed app is running. Saved window state is
  # ignored, and the demo window never saves its frame (App/macOS/ScreenshotWindow.swift).
  open -n "$app" --args -ApplePersistenceIgnoreState YES -InMemoryVault -DemoVault \
    -ScreenshotWindowSize 1100x700 "${arguments[@]}"
  pid=""
  for _ in $(seq 40); do
    pid="$(pgrep -nf "^$executable" || true)"
    [ -n "$pid" ] && break
    sleep 0.25
  done
  [ -n "$pid" ] || { echo "The app didn't start" >&2; exit 1; }
  window="$(swift scripts/mac-screenshot.swift window "$pid")"
  sleep 3
  if ! screencapture -l "$window" -x "$work/$name.png"; then
    kill "$pid"
    echo "Can't capture the window: give the terminal app Screen Recording permission." >&2
    exit 1
  fi
  kill "$pid"
  swift scripts/mac-screenshot.swift frame "$work/$name.png" "$out/$name.png"
  echo "   $out/$name.png"
  sleep 1
done
