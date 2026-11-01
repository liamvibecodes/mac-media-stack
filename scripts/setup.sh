#!/bin/bash
# Media Stack Setup Helper
# Creates all required folders and prepares the .env file.
# Usage: bash scripts/setup.sh [--media-dir DIR] [--config-dir DIR] [--help]

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/stack-config.sh
source "$SCRIPT_DIR/scripts/lib/stack-config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$SCRIPT_DIR/scripts/lib/ui.sh"

usage() {
    cat <<EOF
Usage: bash scripts/setup.sh [OPTIONS]

Creates Media folder structure and generates .env from .env.example.

Options:
  --media-dir DIR   Media root path (default: ~/Media)
  --config-dir DIR  App config/database path (default: <media-dir>/config).
                    Keep this on a local disk if the media dir is on a NAS.
  --help            Show this help message
EOF
}

MEDIA_DIR_OVERRIDE=""
CONFIG_DIR_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                usage
                exit 1
            fi
            MEDIA_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --config-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --config-dir"
                usage
                exit 1
            fi
            CONFIG_DIR_OVERRIDE="$2"
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

echo ""
echo "=============================="
echo "  Media Stack Setup"
echo "=============================="
echo ""

# Detect current user and home directory
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
MEDIA_DIR="${MEDIA_DIR_OVERRIDE:-$HOME_DIR/Media}"
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"

# Config dir priority: --config-dir -> existing .env CONFIG_DIR -> <media-dir>/config
CONFIG_DIR="${CONFIG_DIR_OVERRIDE:-$(config_get_path CONFIG_DIR "$MEDIA_DIR/config")}"
CONFIG_DIR="${CONFIG_DIR/#\~/$HOME}"

echo "Detected user: $CURRENT_USER"
echo "Media folder will be: $MEDIA_DIR"
echo "Config folder will be: $CONFIG_DIR"
echo ""

# Get user ID
USER_PUID=$(id -u)
USER_PGID=$(id -g)

# Create folder structure
echo "Creating folders..."
mkdir -p "$MEDIA_DIR"/{downloads,movies,tvshows,logs}
mkdir -p "$CONFIG_DIR"/{rtorrent,flood,emby,prowlarr,sonarr,radarr,bazarr,seerr}
echo -e "  ${GREEN}Done${NC}"
echo ""

# Create .env from example if it doesn't exist
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${YELLOW}Note:${NC} .env already exists. Skipping creation."
    echo "  Edit it manually if you need to change values."
else
    echo "Creating .env file..."
    sed "s|^CONFIG_DIR=.*|CONFIG_DIR=$CONFIG_DIR|" "$SCRIPT_DIR/.env.example" \
        | sed "s|/Users/YOURUSERNAME/Media|$MEDIA_DIR|g" \
        | sed "s|PUID=501|PUID=$USER_PUID|g" \
        | sed "s|PGID=20|PGID=$USER_PGID|g" \
        > "$SCRIPT_DIR/.env"
    chmod 600 "$SCRIPT_DIR/.env"
    echo -e "  ${GREEN}Done${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT:${NC} You still need to add your VPN keys to .env"
    echo "  Open .env in a text editor and fill in:"
    echo "    - WIREGUARD_PRIVATE_KEY"
    echo "    - WIREGUARD_ADDRESSES"
    echo "  (from your ProtonVPN or Mullvad WireGuard config; set VPN_PROVIDER in .env)"
fi

echo ""
echo "=============================="
echo "  Setup complete!"
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Add VPN keys to .env (if not already done)"
echo "  2. Run: docker compose up -d"
echo "  3. Run: bash scripts/health-check.sh"
echo "  4. Follow the rest of SETUP.md for Emby + app configuration"
echo ""
