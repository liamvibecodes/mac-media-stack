#!/bin/bash
# Mac Media Stack - One-Shot Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack/main/bootstrap.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "=============================="
echo "  Mac Media Stack Installer"
echo "=============================="
echo ""

# Detect container runtime
detect_installed_runtime() {
    local has_orbstack=0
    local has_docker_desktop=0

    if [[ -d "/Applications/OrbStack.app" ]] || command -v orbstack &>/dev/null; then
        has_orbstack=1
    fi
    if [[ -d "/Applications/Docker.app" ]]; then
        has_docker_desktop=1
    fi

    if [[ $has_orbstack -eq 1 && $has_docker_desktop -eq 1 ]]; then
        echo "OrbStack or Docker Desktop"
    elif [[ $has_orbstack -eq 1 ]]; then
        echo "OrbStack"
    elif [[ $has_docker_desktop -eq 1 ]]; then
        echo "Docker Desktop"
    else
        echo "none"
    fi
}

detect_running_runtime() {
    local os_name
    os_name=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)
    if [[ "$os_name" == *"OrbStack"* ]]; then
        echo "OrbStack"
    elif [[ "$os_name" == *"Docker Desktop"* ]]; then
        echo "Docker Desktop"
    else
        echo "Docker"
    fi
}

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
echo -e "${GREEN}OK${NC}  $RUNTIME is running"

# Check Plex
if [[ -d "/Applications/Plex Media Server.app" ]] || pgrep -x "Plex Media Server" &>/dev/null; then
    echo -e "${GREEN}OK${NC}  Plex detected"
else
    echo -e "${YELLOW}WARN${NC}  Plex not detected. Install from https://www.plex.tv/media-server-downloads/"
    echo "  You can continue and install Plex later."
fi

# Check git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}..${NC}  git not found, installing Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    echo "  Click Install when prompted, then run this again."
    exit 1
fi

echo ""

# Clone
INSTALL_DIR="$HOME/mac-media-stack"
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
    git clone https://github.com/liamvibecodes/mac-media-stack.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

echo ""

# Setup
echo -e "${CYAN}Running setup...${NC}"
bash scripts/setup.sh

echo ""

# VPN keys
if grep -q "your_wireguard_private_key_here" .env 2>/dev/null; then
    echo -e "${CYAN}VPN Configuration${NC}"
    echo ""
    echo "You need your ProtonVPN WireGuard credentials."
    echo "If someone gave you a private key and address, enter them now."
    echo ""
    read -s -p "  WireGuard Private Key: " vpn_key
    echo ""
    read -p "  WireGuard Address (e.g. 10.2.0.2/32): " vpn_addr

    if [[ -n "$vpn_key" && -n "$vpn_addr" ]]; then
        sed -i '' "s|WIREGUARD_PRIVATE_KEY=.*|WIREGUARD_PRIVATE_KEY=$vpn_key|" .env
        sed -i '' "s|WIREGUARD_ADDRESSES=.*|WIREGUARD_ADDRESSES=$vpn_addr|" .env
        echo -e "  ${GREEN}VPN keys saved${NC}"
    else
        echo -e "  ${YELLOW}Skipped.${NC} Edit .env manually before starting."
        echo "  Run: open -a TextEdit $INSTALL_DIR/.env"
    fi
fi

echo ""

# Start stack
echo -e "${CYAN}Starting media stack...${NC}"
echo "  (First run downloads ~2-3 GB, this may take a few minutes)"
echo ""
docker compose up -d

echo ""
echo "Waiting 30 seconds for services to initialize..."
sleep 30

# Configure
echo ""
bash scripts/configure.sh

# Auto-heal
echo ""
echo -e "${CYAN}Installing auto-healer...${NC}"
bash scripts/install-auto-heal.sh

echo ""
echo "=============================="
echo -e "  ${GREEN}Installation complete!${NC}"
echo "=============================="
echo ""
echo "  Seerr (browse/request):  http://localhost:5055"
echo "  Plex (watch):            http://localhost:32400/web"
echo ""
echo "  Next: Set up Plex libraries (Settings > Libraries > Add)"
echo "    - Movies: ~/Media/Movies"
echo "    - TV Shows: ~/Media/TV Shows"
echo ""
