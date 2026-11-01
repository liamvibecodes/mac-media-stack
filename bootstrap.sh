#!/bin/bash
# Mac Media Stack - One-Shot Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/alexgrpopa/mac-media-stack/main/bootstrap.sh | bash

set -euo pipefail

# Colours for the messages printed before the repo is cloned. After the clone the
# shared library (scripts/lib/ui.sh) takes over; this script may run via curl | bash,
# so it cannot depend on the library until then.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MEDIA_DIR="$HOME/Media"
INSTALL_DIR="$HOME/mac-media-stack"
NON_INTERACTIVE=false
VPN_PROVIDER=protonvpn
PROXY=false
AUTO_UPDATE=false

usage() {
    cat <<EOF
Usage: bash bootstrap.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: ~/Media)
  --install-dir DIR     Repo install directory (default: ~/mac-media-stack)
  --proxy               Friendly hostnames (seerr.media.lan, radarr.media.lan, ...) via Caddy
  --auto-update         Update every image to its latest version, daily at 04:00
  --mullvad             Use Mullvad instead of ProtonVPN (no port forwarding)
  --non-interactive     Skip interactive prompts (manual Seerr wiring required)
  --help                Show this help message

Examples:
  bash bootstrap.sh
  bash bootstrap.sh --media-dir /Volumes/T9/Media
  bash bootstrap.sh --media-dir /Volumes/T9/Media --non-interactive
  bash bootstrap.sh --mullvad
  bash bootstrap.sh --proxy
  bash bootstrap.sh --auto-update
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
        --install-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --install-dir"
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --mullvad)
            VPN_PROVIDER=mullvad
            shift
            ;;
        --proxy)
            PROXY=true
            shift
            ;;
        --auto-update)
            AUTO_UPDATE=true
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
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

MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

echo ""
echo "=============================="
echo "  Mac Media Stack Installer"
echo "=============================="
echo ""

# Check git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}..${NC}  git not found, installing Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    echo "  Click Install when prompted, then run this again."
    exit 1
fi

echo "Install dir: $INSTALL_DIR"
echo "Media dir:   $MEDIA_DIR"
echo ""

# Clone
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}Note:${NC} $INSTALL_DIR already exists. Pulling latest..."
    if ! git -C "$INSTALL_DIR" pull --ff-only; then
        echo -e "${RED}Failed to update existing repo at $INSTALL_DIR.${NC}"
        echo "Resolve local git issues, then re-run bootstrap."
        echo "Suggested check: cd $INSTALL_DIR && git status"
        exit 1
    fi
else
    echo -e "${CYAN}Cloning repo...${NC}"
    git clone https://github.com/alexgrpopa/mac-media-stack.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

# Everything below uses the shared libraries from the checkout.
# shellcheck source=scripts/lib/runtime.sh
source scripts/lib/runtime.sh
# shellcheck source=scripts/lib/topology.sh
source scripts/lib/topology.sh

echo ""

# Detect container runtime
INSTALLED_RUNTIME=$(detect_installed_runtime)

if ! docker info &>/dev/null; then
    if [[ "$INSTALLED_RUNTIME" == "none" ]]; then
        echo -e "${RED}No container runtime found.${NC}"
        echo ""
        echo "Install one of these:"
        echo "  OrbStack (recommended):  brew install --cask orbstack"
        echo "  Docker Desktop:          https://www.docker.com/products/docker-desktop/"
    else
        echo -e "${RED}No container runtime is running.${NC}"
        echo "Start $INSTALLED_RUNTIME, wait for it to start, then run this again."
    fi
    exit 1
fi
RUNTIME=$(detect_running_runtime)
ui_ok "$RUNTIME is running"

echo ""

# Setup
echo -e "${CYAN}Running setup...${NC}"
bash scripts/setup.sh --media-dir "$MEDIA_DIR"

# Record the install choices in .env (also selects the optional compose file)
stack_apply_choices "$PROXY"
# Mullvad has no port forwarding, so it is switched off. .env.example already defaults to ProtonVPN.
if [[ "$VPN_PROVIDER" == "mullvad" ]]; then
    config_set VPN_PROVIDER mullvad
    config_set VPN_COUNTRIES Denmark
    config_set VPN_PORT_FORWARDING off
fi

echo ""

# VPN keys
if [[ "$(config_get WIREGUARD_PRIVATE_KEY)" == "your_wireguard_private_key_here" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}WARN${NC}  Non-interactive mode: VPN placeholders still present in .env"
        echo "  Update WIREGUARD_PRIVATE_KEY and WIREGUARD_ADDRESSES before using the stack."
    else
        echo -e "${CYAN}VPN Configuration${NC}"
        echo ""
        if [[ "$VPN_PROVIDER" == "mullvad" ]]; then
            echo "You need your Mullvad WireGuard credentials (mullvad.net/account > WireGuard configuration > Linux)."
            echo "Address: use the IPv4 part only (e.g. 10.66.12.34/32)."
        else
            echo "You need your ProtonVPN WireGuard credentials."
        fi
        echo "If someone gave you a private key and address, enter them now."
        echo ""

        vpn_key=""
        while [[ -z "$vpn_key" ]]; do
            read -s -p "  WireGuard Private Key: " vpn_key
            echo ""
            if [[ -z "$vpn_key" ]]; then
                echo -e "  ${RED}Private key cannot be empty. Please try again.${NC}"
            fi
        done

        read -p "  WireGuard Address (IPv4, e.g. 10.2.0.2/32): " vpn_addr

        if [[ -n "$vpn_addr" ]]; then
            config_set WIREGUARD_PRIVATE_KEY "$vpn_key"
            config_set WIREGUARD_ADDRESSES "$vpn_addr"
            echo -e "  ${GREEN}VPN keys saved${NC}"
        else
            echo -e "  ${YELLOW}Skipped.${NC} Edit .env manually before starting."
            echo "  Run: open -a TextEdit $INSTALL_DIR/.env"
        fi
    fi
fi

echo ""

# Preflight
echo -e "${CYAN}Running preflight checks...${NC}"
if ! bash scripts/doctor.sh --media-dir "$MEDIA_DIR"; then
    echo ""
    echo -e "${RED}Preflight checks failed.${NC} Fix the FAIL items above, then re-run bootstrap."
    exit 1
fi

echo ""

# Start stack
echo -e "${CYAN}Starting media stack...${NC}"
echo "  (First run downloads ~2-3 GB, this may take a few minutes)"
echo ""
if ! docker compose up -d; then
    echo -e "${RED}Error: docker compose failed to start${NC}"
    echo "Check logs with: docker compose logs"
    exit 1
fi

echo ""
echo "Waiting for core services..."
topology_wait_ready 45 warn || true

# Configure
echo ""
if [[ "$NON_INTERACTIVE" == true ]]; then
    bash scripts/configure.sh --non-interactive
else
    bash scripts/configure.sh
fi

# Auto-heal
echo ""
echo -e "${CYAN}Installing auto-healer...${NC}"
bash scripts/install-auto-heal.sh

if [[ "$AUTO_UPDATE" == true ]]; then
    echo ""
    echo -e "${CYAN}Installing auto-update...${NC}"
    bash scripts/install-auto-update.sh
fi

echo ""
echo "=============================="
echo -e "  ${GREEN}Installation complete!${NC}"
echo "=============================="
echo ""
echo "  Seerr (browse/request):  $(topology_url seerr)"
echo "  Emby (watch):            $(topology_url emby)"
echo "  Flood (downloads):       $(topology_url flood)"
echo "  Media location:          $MEDIA_DIR"
if [[ "$PROXY" == true ]]; then
    echo ""
    echo "  Friendly names:          http://$(stack_proxy_domain)  (seerr., radarr., sonarr., ... prefixes)"
    echo "  Make them resolve:       bash scripts/setup-hosts.sh  (or add DNS records on your router, see SETUP.md)"
fi
echo ""
echo "  Next: Set up Emby libraries at $(topology_url emby)"
echo "    - Movies: /data/movies"
echo "    - TV shows: /data/tvshows"
echo ""
