#!/bin/bash
# Installs (or reinstalls) the launchd job that runs ios-device-refresh.sh
# every Monday and Thursday at 10:00. A run missed while the Mac sleeps
# fires on wake. Copies the script and clones the repo under
# ~/Library/Application Support/Astral, since launchd jobs can't read
# ~/Desktop. Re-run after editing the script. Pass --uninstall to remove the
# job (the clone and DerivedData are left in place).

set -euo pipefail

LABEL="com.astral.device-refresh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SUPPORT_DIR="$HOME/Library/Application Support/Astral"
SCRIPT="$SUPPORT_DIR/ios-device-refresh.sh"
CLONE_DIR="$SUPPORT_DIR/repo"
LOG_DIR="$HOME/Library/Logs/Astral"
SOURCE_REPO="$(cd "$(dirname "$0")/.." && pwd)"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$PLIST"
    echo "Removed $LABEL"
    exit 0
fi

mkdir -p "$LOG_DIR" "$HOME/Library/LaunchAgents" "$SUPPORT_DIR"
install -m 755 "$SOURCE_REPO/scripts/ios-device-refresh.sh" "$SCRIPT"

if [[ ! -d "$CLONE_DIR/.git" ]]; then
    git clone --quiet --branch development "$(git -C "$SOURCE_REPO" remote get-url origin)" "$CLONE_DIR"
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <key>StartCalendarInterval</key>
    <array>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
        <dict><key>Weekday</key><integer>4</integer><key>Hour</key><integer>10</integer><key>Minute</key><integer>0</integer></dict>
    </array>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/device-refresh.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/device-refresh.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed $LABEL (Mon + Thu 10:00). Log: $LOG_DIR/device-refresh.log"
echo "Run now: launchctl kickstart gui/$(id -u)/$LABEL"
