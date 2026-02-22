#!/bin/bash
# Media Stack Auto-Healer
# Runs hourly via launchd. Checks VPN and container health, restarts what's broken.

LOG_DIR="$HOME/Media/logs"
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

# Check VPN tunnel
vpn_ip=$(docker exec gluetun sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null)
vpn_iface=$(docker exec gluetun sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null)
vpn_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' gluetun 2>/dev/null || true)

if [[ -z "$vpn_ip" || -z "$vpn_iface" || "$vpn_health" == "unhealthy" ]]; then
    log "WARN: VPN status unhealthy (health=${vpn_health:-unknown}, ip=${vpn_ip:-none}, iface=${vpn_iface:-none}). Restarting gluetun..."
    docker restart gluetun >> "$LOG" 2>&1
    sleep 15
    vpn_ip=$(docker exec gluetun sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null)
    vpn_iface=$(docker exec gluetun sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null)
    vpn_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' gluetun 2>/dev/null || true)
    if [[ -n "$vpn_ip" && -n "$vpn_iface" && "$vpn_health" != "unhealthy" ]]; then
        log "OK: VPN recovered (IP: $vpn_ip, iface=$vpn_iface, health=${vpn_health:-unknown})"
        ((HEALED++))
    else
        log "ERROR: VPN still down after restart (health=${vpn_health:-unknown}, ip=${vpn_ip:-none}, iface=${vpn_iface:-none})"
    fi
else
    log "OK: VPN active (IP: $vpn_ip, iface=$vpn_iface, health=${vpn_health:-unknown})"
fi

# Check core containers are running
for name in gluetun qbittorrent prowlarr sonarr radarr bazarr flaresolverr seerr; do
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    if [[ "$state" != "running" ]]; then
        log "WARN: $name is $state. Starting..."
        docker start "$name" >> "$LOG" 2>&1
        ((HEALED++))
    fi
done

if [[ $HEALED -gt 0 ]]; then
    log "Healed $HEALED issue(s)"
else
    log "All healthy"
fi
