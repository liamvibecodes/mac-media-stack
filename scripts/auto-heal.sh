#!/bin/bash
# Media Stack Auto-Healer
# Runs hourly via launchd. Checks VPN and container health, restarts what's broken.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/topology.sh
source "$SCRIPT_DIR/lib/topology.sh"
# shellcheck source=scripts/lib/vpn.sh
source "$SCRIPT_DIR/lib/vpn.sh"

# Local disk on purpose: the media share may be unmounted or read-only
LOG_DIR="${AUTO_HEAL_LOG_DIR:-$HOME/Library/Logs/media-stack}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/auto-heal.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() { echo "$(timestamp) $1" >> "$LOG"; }

# Trim log to last 500 lines
if [[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 500 ]]; then
    tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log "--- Health check started ---"

# Check Docker is running
if ! docker info &>/dev/null; then
    log "ERROR: Container runtime not running. Cannot heal."
    exit 1
fi

HEALED=0

vpn_summary() { echo "health=$VPN_HEALTH, ip=${VPN_IP:-none}, iface=${VPN_IFACE:-none}"; }

# Check VPN tunnel
if vpn_probe; then
    log "OK: VPN active (IP: $VPN_IP, iface=$VPN_IFACE, health=$VPN_HEALTH)"
else
    log "WARN: VPN status unhealthy ($(vpn_summary)). Restarting gluetun..."
    docker restart "$VPN_CONTAINER" >> "$LOG" 2>&1
    sleep 15
    if vpn_probe; then
        log "OK: VPN recovered (IP: $VPN_IP, iface=$VPN_IFACE, health=$VPN_HEALTH)"
        HEALED=$((HEALED + 1))
    else
        log "ERROR: VPN still down after restart ($(vpn_summary))"
    fi
fi

# Check every container in the stack is running
while IFS='|' read -r name label url probe; do
    [[ -n "$name" ]] || continue
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    if [[ "$state" != "running" ]]; then
        log "WARN: $name is ${state:-not found}. Starting..."
        docker start "$name" >> "$LOG" 2>&1
        HEALED=$((HEALED + 1))
    fi
done < <(topology_entries)

if [[ $HEALED -gt 0 ]]; then
    log "Healed $HEALED issue(s)"
else
    log "All healthy"
fi
