#!/bin/bash
# Media Stack preflight checks (non-destructive)
# Usage: bash scripts/doctor.sh [--media-dir DIR] [--help]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/topology.sh
source "$SCRIPT_DIR/scripts/lib/topology.sh"
ENV_FILE="$(stack_env_file)"
MEDIA_DIR=""

PASS=0
WARN=0
FAIL=0

usage() {
    cat <<EOF
Usage: bash scripts/doctor.sh [OPTIONS]

Run preflight checks before first startup.

Options:
  --media-dir DIR   Media root path (default: from .env, otherwise ~/Media)
  --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                exit 1
            fi
            MEDIA_DIR="$2"
            shift 2
            ;;
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
done

MEDIA_DIR="${MEDIA_DIR:-$(stack_media_dir)}"
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
CONFIG_DIR="$(config_get_path CONFIG_DIR "$MEDIA_DIR/config")"
PROXY_DOMAIN="$(stack_proxy_domain)"

ok() { ui_ok "$1"; PASS=$((PASS + 1)); }
warn() { ui_warn "$1"; WARN=$((WARN + 1)); }
fail() { ui_fail "$1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=============================="
echo "  Media Stack Doctor"
echo "=============================="
echo ""
echo -e "  ${CYAN}Info${NC}  Project: $SCRIPT_DIR"
echo -e "  ${CYAN}Info${NC}  Media dir: $MEDIA_DIR"
echo ""

# Core tools
for cmd in docker curl grep sed awk; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Command found: $cmd"
    else
        fail "Missing command: $cmd"
    fi
done

# Container runtime
if docker info >/dev/null 2>&1; then
    runtime=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || echo "Docker")
    ok "Container runtime running ($runtime)"
else
    fail "Container runtime is not running"
fi

# .env
if [[ -f "$ENV_FILE" ]]; then
    ok ".env exists"
    if [[ "$(config_get WIREGUARD_PRIVATE_KEY)" == "your_wireguard_private_key_here" ]]; then
        fail "WIREGUARD_PRIVATE_KEY is still a placeholder in .env"
    else
        ok "WIREGUARD_PRIVATE_KEY appears set"
    fi

    if [[ "$(config_get WIREGUARD_ADDRESSES)" == "your_wireguard_address_here" ]]; then
        fail "WIREGUARD_ADDRESSES is still a placeholder in .env"
    else
        ok "WIREGUARD_ADDRESSES appears set"
    fi

    vpn_provider="$(config_get VPN_PROVIDER protonvpn)"
    vpn_pf="$(config_get VPN_PORT_FORWARDING on)"
    if [[ "$vpn_provider" == "mullvad" && "$vpn_pf" != "off" ]]; then
        fail "VPN_PROVIDER=mullvad needs VPN_PORT_FORWARDING=off in .env (Mullvad has no port forwarding)"
    else
        ok "VPN provider: $vpn_provider (port forwarding $vpn_pf)"
    fi
else
    fail ".env is missing (run: bash scripts/setup.sh)"
fi

# Media directories
for dir in "$MEDIA_DIR" "$MEDIA_DIR/downloads" "$MEDIA_DIR/movies" "$MEDIA_DIR/tvshows" "$CONFIG_DIR"; do
    if [[ -d "$dir" ]]; then
        ok "Directory exists: $dir"
    else
        warn "Directory missing: $dir"
    fi
done

# Compose render
if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]] && [[ -f "$ENV_FILE" ]]; then
    if (cd "$SCRIPT_DIR" && docker compose config >/dev/null 2>&1); then
        ok "docker-compose.yml renders with current .env"
    else
        fail "docker-compose.yml failed to render (check .env values)"
    fi
fi

# Port checks
PORTS="$(topology_ports)"
for port in $PORTS; do
    owner=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}' || true)
    if [[ -z "$owner" ]]; then
        ok "Port $port is free"
    else
        warn "Port $port already in use by $owner"
    fi
done

# Hostnames (only when the proxy override is enabled)
if stack_proxy_enabled; then
    if dscacheutil -q host -a name "seerr.$PROXY_DOMAIN" 2>/dev/null | grep -Eq 'ip(v6)?_address'; then
        ok "Hostnames: seerr.$PROXY_DOMAIN resolves"
    else
        warn "seerr.$PROXY_DOMAIN does not resolve (run: bash scripts/setup-hosts.sh, or add DNS records on your router)"
    fi
fi

echo ""
echo "=============================="
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failed${NC}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "Resolve FAIL items first, then run this again."
    exit 1
fi

echo "Preflight checks passed."
