#!/bin/bash
# Mac Media Stack - One-Shot Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack/main/bootstrap.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MEDIA_DIR="$HOME/Media"
INSTALL_DIR="$HOME/mac-media-stack"
NON_INTERACTIVE=false

usage() {
    cat <<EOF
Usage: bash bootstrap.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: ~/Media)
  --install-dir DIR     Repo install directory (default: ~/mac-media-stack)
  --non-interactive     Skip interactive prompts (manual Seerr wiring required)
  --help                Show this help message

Examples:
  bash bootstrap.sh
  bash bootstrap.sh --media-dir /Volumes/T9/Media
  bash bootstrap.sh --media-dir /Volumes/T9/Media --non-interactive
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

wait_for_service() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-45}"
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true)
        if [[ "$status" =~ ^(200|301|302|401|403)$ ]]; then
            echo -e "  ${GREEN}OK${NC}  $name is reachable"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done

    echo -e "  ${YELLOW}WARN${NC}  $name is not reachable yet (continuing anyway)"
    return 1
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
    git clone https://github.com/liamvibecodes/mac-media-stack.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

echo ""

# Setup
echo -e "${CYAN}Running setup...${NC}"
bash scripts/setup.sh --media-dir "$MEDIA_DIR"

echo ""

# VPN keys
if grep -q "your_wireguard_private_key_here" .env 2>/dev/null; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}WARN${NC}  Non-interactive mode: VPN placeholders still present in .env"
        echo "  Update WIREGUARD_PRIVATE_KEY and WIREGUARD_ADDRESSES before using the stack."
    else
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
docker compose up -d

echo ""
echo "Waiting for core services..."
wait_for_service "qBittorrent" "http://localhost:8080" || true
wait_for_service "Prowlarr" "http://localhost:9696" || true
wait_for_service "Radarr" "http://localhost:7878" || true
wait_for_service "Sonarr" "http://localhost:8989" || true
wait_for_service "Seerr" "http://localhost:5055" || true

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

echo ""
echo "=============================="
echo -e "  ${GREEN}Installation complete!${NC}"
echo "=============================="
echo ""
echo "  Seerr (browse/request):  http://localhost:5055"
echo "  Plex (watch):            http://localhost:32400/web"
echo ""
echo "  Media location:          $MEDIA_DIR"
echo ""
echo "  Next: Set up Plex libraries (Settings > Libraries > Add)"
echo "    - Movies: $MEDIA_DIR/Movies"
echo "    - TV Shows: $MEDIA_DIR/TV Shows"
echo ""
