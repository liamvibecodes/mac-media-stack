#!/bin/bash
# Installs the auto-heal launchd job (runs hourly).
# Usage: bash scripts/install-auto-heal.sh [--help]

set -euo pipefail

GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Media/logs/launchd"
PLIST_NAME="com.media-stack.auto-heal"
PLIST_PATH="$LAUNCH_DIR/$PLIST_NAME.plist"

usage() {
    cat <<EOF
Usage: bash scripts/install-auto-heal.sh

Installs the hourly auto-heal launchd job.

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
        <string>$SCRIPT_DIR/auto-heal.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/auto-heal.out.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/auto-heal.err.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo -e "${GREEN}Auto-heal installed.${NC} Runs every hour + on login."
echo "Logs: ~/Media/logs/auto-heal.log and ~/Media/logs/launchd/"
echo ""
echo "To uninstall: launchctl unload $PLIST_PATH && rm $PLIST_PATH"
