#!/bin/bash
# Adds (or removes) the stack's hostnames in /etc/hosts so names like
# seerr.media.lan resolve to this Mac. Needs sudo to edit /etc/hosts.
#
# Usage:
#   bash scripts/setup-hosts.sh            add/update the entries
#   bash scripts/setup-hosts.sh --remove   remove them again
#   bash scripts/setup-hosts.sh --print    show the entries without changing anything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/stack-config.sh
source "$SCRIPT_DIR/lib/stack-config.sh"
HOSTS_FILE="/etc/hosts"
BEGIN_MARK="# >>> mac-media-stack >>>"
END_MARK="# <<< mac-media-stack <<<"
NAMES=(seerr radarr sonarr prowlarr bazarr emby flood rutorrent)

MODE=add
case "${1:-}" in
    --remove) MODE=remove ;;
    --print) MODE=print ;;
    "") ;;
    *) echo "Usage: bash scripts/setup-hosts.sh [--remove|--print]"; exit 1 ;;
esac

PROXY_DOMAIN="$(stack_proxy_domain)"

entry="127.0.0.1 $PROXY_DOMAIN"
for name in "${NAMES[@]}"; do
    entry+=" $name.$PROXY_DOMAIN"
done

block="$BEGIN_MARK
$entry
$END_MARK"

if [[ "$MODE" == "print" ]]; then
    echo "$block"
    exit 0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Copy /etc/hosts without any previous block of ours.
awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip { print }
' "$HOSTS_FILE" > "$tmp"

if [[ "$MODE" == "add" ]]; then
    printf '%s\n' "$block" >> "$tmp"
fi

if cmp -s "$tmp" "$HOSTS_FILE"; then
    echo "Nothing to change in $HOSTS_FILE"
    exit 0
fi

echo "Updating $HOSTS_FILE (sudo password may be requested)..."
sudo cp "$tmp" "$HOSTS_FILE"
sudo dscacheutil -flushcache 2>/dev/null || true
sudo killall -HUP mDNSResponder 2>/dev/null || true

if [[ "$MODE" == "add" ]]; then
    echo "Done. Open http://$PROXY_DOMAIN for the list of services."
else
    echo "Removed the mac-media-stack entries."
fi
