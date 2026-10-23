#!/bin/bash
# Captures App Store screenshots from the iOS simulators, using the fake demo vault
# (-InMemoryVault -DemoVault) and the screenshot launch arguments. Run through `task screenshots`.
#   scripts/screenshots.sh <derived data dir> <output dir>
set -euo pipefail

derived="$1"
out="$2"
bundle=com.datoos.silicon-wallet
app="$derived/Build/Products/Debug-iphonesimulator/SiliconWallet.app"

# name|simulator
devices=(
  "iPhone-6.9|iPhone 17 Pro Max"
  "iPhone-6.3|iPhone 17"
  "iPad-13|iPad Pro 13-inch (M5)"
)

# name|launch arguments, separated by ";" so values can contain spaces
shots=(
  "1-home|-ScreenshotHome"
  "2-entry|-ScreenshotSidebar;Logins;-ScreenshotEntry;Example Mail"
  "3-card|-ScreenshotSidebar;favorites;-ScreenshotEntry;Example Visa"
  "4-notes|-ScreenshotSidebar;Secure Notes;-ScreenshotEntry;Wi-Fi at Home"
  "5-locked|-Locked"
)

for device in "${devices[@]}"; do
  name="${device%%|*}"
  simulator="${device#*|}"
  udid="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)['devices']
for runtime, devices in sorted(data.items(), reverse=True):
    for d in devices:
        if d['name'] == sys.argv[1]:
            print(d['udid']); sys.exit()
" "$simulator")"
  if [ -z "$udid" ]; then
    echo "No simulator named '$simulator'; see: xcrun simctl list devices available" >&2
    exit 1
  fi

  echo "== $name ($simulator)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  xcrun simctl ui "$udid" appearance light
  xcrun simctl install "$udid" "$app"
  # A freshly booted simulator shows welcome notifications for a few seconds; let them pass.
  xcrun simctl launch "$udid" "$bundle" -InMemoryVault -DemoVault >/dev/null
  sleep 20
  mkdir -p "$out/$name"

  for shot in "${shots[@]}"; do
    shot_name="${shot%%|*}"
    IFS=";" read -r -a arguments <<< "${shot#*|}"
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$udid" "$bundle" -InMemoryVault -DemoVault "${arguments[@]}" >/dev/null
    sleep 4
    xcrun simctl io "$udid" screenshot --type png "$out/$name/$shot_name.png" >/dev/null 2>&1
    echo "   $out/$name/$shot_name.png"
  done

  xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
done
