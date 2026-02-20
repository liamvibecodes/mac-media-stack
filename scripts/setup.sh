#!/bin/bash
# Media Stack Setup Helper
# Creates all required folders and prepares the .env file.

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "=============================="
echo "  Media Stack Setup"
echo "=============================="
echo ""

# Detect current user and home directory
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
MEDIA_DIR="$HOME_DIR/Media"

echo "Detected user: $CURRENT_USER"
echo "Media folder will be: $MEDIA_DIR"
echo ""

# Get user ID
USER_PUID=$(id -u)
USER_PGID=$(id -g)

# Create folder structure
echo "Creating folders..."
mkdir -p "$MEDIA_DIR"/{config,Downloads,Movies,"TV Shows",logs}
mkdir -p "$MEDIA_DIR"/config/{qbittorrent,prowlarr,sonarr,radarr,bazarr,seerr}
echo -e "  ${GREEN}Done${NC}"
echo ""

# Create .env from example if it doesn't exist
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${YELLOW}Note:${NC} .env already exists. Skipping creation."
    echo "  Edit it manually if you need to change values."
else
    echo "Creating .env file..."
    sed "s|/Users/YOURUSERNAME/Media|$MEDIA_DIR|g" "$SCRIPT_DIR/.env.example" \
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
    echo "  (from your ProtonVPN account or provided to you)"
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
echo "  4. Follow the rest of SETUP.md for Plex + app configuration"
echo ""
