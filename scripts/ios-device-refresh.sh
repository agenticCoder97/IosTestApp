#!/bin/bash
# Rebuilds Astral from origin/development and reinstalls it on the iPhone so
# the free-account signature (7-day expiry) never lapses. Installing over the
# existing app keeps its data. Run by the launchd job that
# ios-device-refresh-install.sh sets up.
#
# Builds from its own clone under ~/Library/Application Support/Astral, not
# the Desktop checkout: macOS blocks launchd jobs from reading ~/Desktop.
#
# The phone must be reachable: plugged in, or paired over Wi-Fi
# (Xcode > Devices and Simulators > "Connect via network").

set -euo pipefail

DEVICE_ID="${ASTRAL_DEVICE_ID:-00008140-000554842109801C}"
BRANCH="${ASTRAL_REFRESH_BRANCH:-development}"
SUPPORT_DIR="$HOME/Library/Application Support/Astral"
CLONE_DIR="$SUPPORT_DIR/repo"
DERIVED_DATA="$SUPPORT_DIR/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release-iphoneos/Astral.app"

notify_failure() {
    osascript -e "display notification \"$1 See ~/Library/Logs/Astral/device-refresh.log\" with title \"Astral refresh failed\"" || true
}
trap 'notify_failure "Step failed (line $LINENO)."' ERR

echo "=== $(date '+%Y-%m-%d %H:%M:%S') refresh start ==="

device_state="$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE_ID" || true)"
if [[ -z "$device_state" || "$device_state" == *unavailable* ]]; then
    trap - ERR
    notify_failure "iPhone not reachable. Unlock it on the same Wi-Fi, or plug it in."
    echo "iPhone $DEVICE_ID not reachable; skipping."
    exit 1
fi

git -C "$CLONE_DIR" fetch --quiet origin "$BRANCH"
git -C "$CLONE_DIR" reset --quiet --hard "origin/$BRANCH"
echo "Building $(git -C "$CLONE_DIR" log -1 --format='%h %s')"

# Xcode reuses a cached profile until it expires, so a run a day before
# expiry would install an app that dies the next day. Move the cached
# Astral profiles aside so every run gets a fresh 7-day one; put them back
# if the build fails.
PROFILES_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
STASH_DIR="$SUPPORT_DIR/stashed-profiles"
rm -rf "$STASH_DIR" && mkdir -p "$STASH_DIR"
for profile in "$PROFILES_DIR"/*.mobileprovision; do
    [[ -e "$profile" ]] || continue
    if security cms -D -i "$profile" 2>/dev/null | grep -q "com.astral.reader"; then
        mv "$profile" "$STASH_DIR/"
    fi
done
restore_profiles() { mv "$STASH_DIR"/*.mobileprovision "$PROFILES_DIR/" 2>/dev/null || true; }
trap 'restore_profiles; notify_failure "Step failed (line $LINENO)."' ERR

xcodebuild \
    -project "$CLONE_DIR/ios/Astral/Astral.xcodeproj" \
    -scheme Astral \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -quiet \
    build

xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') refresh done ==="
