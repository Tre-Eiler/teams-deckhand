#!/bin/bash
# Builds the daemon in release mode, installs it to a stable location, and
# registers a LaunchAgent so it starts automatically at login.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.teams-bridge.daemon"
INSTALL_DIR="$HOME/Library/Application Support/TeamsBridge"
LOG_DIR="$HOME/Library/Logs/TeamsBridge"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_NUM="$(id -u)"

mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"

echo "Building release binary..."
swift build -c release

cp ".build/release/teams-bridge-daemon" "$INSTALL_DIR/teams-bridge-daemon"

sed -e "s#__INSTALL_DIR__#$INSTALL_DIR#g" -e "s#__LOG_DIR__#$LOG_DIR#g" \
    "com.teams-bridge.daemon.plist.template" > "$PLIST_PATH"

echo "Registering LaunchAgent..."
launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
sleep 1 # bootout is asynchronous; an immediate bootstrap can race it and fail
launchctl bootstrap "gui/$UID_NUM" "$PLIST_PATH"
launchctl enable "gui/$UID_NUM/$LABEL"

cat <<EOF

Installed:
  binary: $INSTALL_DIR/teams-bridge-daemon
  logs:   $LOG_DIR/daemon.log

IMPORTANT — first run only:
  macOS will prompt for Accessibility permission the first time the daemon
  tries to read Teams. Grant it in System Settings > Privacy & Security >
  Accessibility ("Device Control and Data Access" on macOS 27). Each rebuild
  changes the binary's signature, which leaves the old entry listed but
  stale (switched on yet denied): if the menu bar icon shows a warning, use
  "Reset Permission & Ask Again" in its menu.

Useful commands:
  launchctl kickstart -k "gui/$UID_NUM/$LABEL"   # restart the daemon
  launchctl bootout "gui/$UID_NUM/$LABEL"        # stop and unregister
  tail -f "$LOG_DIR/daemon.log"                  # watch logs
EOF
