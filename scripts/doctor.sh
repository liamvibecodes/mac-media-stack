#!/bin/bash
# Media Stack preflight checks (non-destructive)
# Usage: bash scripts/doctor.sh [--media-dir DIR] [--help]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
MEDIA_DIR="$HOME/Media"

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

if [[ -f "$ENV_FILE" ]]; then
    env_media=$(sed -n 's/^MEDIA_DIR=//p' "$ENV_FILE" | head -1)
    if [[ -n "$env_media" ]]; then
        MEDIA_DIR="$env_media"
    fi
fi
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"

ok() { echo -e "  ${GREEN}OK${NC}   $1"; PASS=$((PASS + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARN=$((WARN + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

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
    if grep -q '^WIREGUARD_PRIVATE_KEY=your_wireguard_private_key_here' "$ENV_FILE"; then
        fail "WIREGUARD_PRIVATE_KEY is still a placeholder in .env"
    else
        ok "WIREGUARD_PRIVATE_KEY appears set"
    fi

    if grep -q '^WIREGUARD_ADDRESSES=your_wireguard_address_here' "$ENV_FILE"; then
        fail "WIREGUARD_ADDRESSES is still a placeholder in .env"
    else
        ok "WIREGUARD_ADDRESSES appears set"
    fi
else
    fail ".env is missing (run: bash scripts/setup.sh)"
fi

# Media directories
for dir in "$MEDIA_DIR" "$MEDIA_DIR/Downloads" "$MEDIA_DIR/Movies" "$MEDIA_DIR/TV Shows" "$MEDIA_DIR/config"; do
    if [[ -d "$dir" ]]; then
        ok "Directory exists: $dir"
    else
        warn "Directory missing: $dir"
    fi
done

# Compose render
if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]] && [[ -f "$ENV_FILE" ]]; then
    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
        ok "docker-compose.yml renders with current .env"
    else
        fail "docker-compose.yml failed to render (check .env values)"
    fi
fi

# Port checks
for port in 5055 32400 9696 8989 7878 8080 6767 8191; do
    owner=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
    if [[ -z "$owner" ]]; then
        ok "Port $port is free"
    else
        warn "Port $port already in use by $owner"
    fi
done

# Plex (optional but recommended)
if [[ -d "/Applications/Plex Media Server.app" ]] || pgrep -x "Plex Media Server" >/dev/null 2>&1; then
    ok "Plex Media Server detected"
else
    warn "Plex Media Server not detected yet"
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
