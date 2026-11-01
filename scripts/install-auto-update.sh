#!/bin/bash
# Installs the auto-update launchd job (runs daily at 04:00).
# Usage: bash scripts/install-auto-update.sh [--help]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

LAUNCH_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="${AUTO_UPDATE_LOG_DIR:-$HOME/Library/Logs/media-stack}"
PLIST_NAME="com.media-stack.auto-update"
PLIST_PATH="$LAUNCH_DIR/$PLIST_NAME.plist"

usage() {
    cat <<EOF
Usage: bash scripts/install-auto-update.sh

Installs the daily (04:00) auto-update launchd job. It moves the stack to the
latest release, like scripts/update-to-latest-release.sh, then restarts what changed.

Options:
  --help    Show this help message
EOF
}

case "${1:-}" in
    "" ) ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac

if [[ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    ui_warn "This folder has tracked local changes. Auto-update skips its run until they are committed or stashed."
fi

mkdir -p "$LAUNCH_DIR" "$LOG_DIR"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/auto-update.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.orbstack/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>4</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/auto-update.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/auto-update.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo -e "${GREEN}Auto-update installed.${NC} Runs every day at 04:00 (or when the Mac wakes, if it was asleep)."
echo "Logs: $LOG_DIR/"
echo ""
echo "To uninstall: launchctl unload $PLIST_PATH && rm $PLIST_PATH"
