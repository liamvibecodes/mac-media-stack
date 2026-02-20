#!/bin/bash
# Media Stack Health Check
# Run this anytime to check if everything is working.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "=============================="
echo "  Media Stack Health Check"
echo "=============================="
echo ""

PASS=0
FAIL=0

check_service() {
    local name="$1"
    local url="$2"
    local expected="${3:-200}"

    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    if [[ "$status" == "$expected" || "$status" == "302" || "$status" == "301" ]]; then
        echo -e "  ${GREEN}OK${NC}  $name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}  $name (got HTTP $status)"
        ((FAIL++))
    fi
}

# Check Docker is running
if docker info &>/dev/null; then
    echo -e "  ${GREEN}OK${NC}  Docker Desktop"
    ((PASS++))
else
    echo -e "  ${RED}FAIL${NC}  Docker Desktop (not running)"
    echo ""
    echo "Start Docker Desktop from your Applications folder and try again."
    exit 1
fi

echo ""

# Check containers are running
echo "Containers:"
for name in gluetun qbittorrent prowlarr sonarr radarr bazarr flaresolverr seerr watchtower; do
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    if [[ "$state" == "running" ]]; then
        echo -e "  ${GREEN}OK${NC}  $name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}  $name (${state:-not found})"
        ((FAIL++))
    fi
done

echo ""
echo "Web UIs:"
check_service "qBittorrent" "http://localhost:8080"
check_service "Prowlarr" "http://localhost:9696"
check_service "Sonarr" "http://localhost:8989"
check_service "Radarr" "http://localhost:7878"
check_service "Bazarr" "http://localhost:6767"
check_service "Seerr" "http://localhost:5055"

echo ""
echo "VPN:"
vpn_ip=$(docker exec gluetun sh -c 'wget -qO- https://ipinfo.io/ip' 2>/dev/null)
local_ip=$(curl -s https://ipinfo.io/ip 2>/dev/null)
if [[ -n "$vpn_ip" && "$vpn_ip" != "$local_ip" ]]; then
    echo -e "  ${GREEN}OK${NC}  VPN active (IP: $vpn_ip)"
    ((PASS++))
elif [[ -z "$vpn_ip" ]]; then
    echo -e "  ${RED}FAIL${NC}  VPN not connected (no response from gluetun)"
    ((FAIL++))
else
    echo -e "  ${RED}FAIL${NC}  VPN IP matches your real IP (tunnel not working)"
    ((FAIL++))
fi

echo ""
echo "Plex:"
plex_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:32400/web" 2>/dev/null)
if [[ "$plex_status" == "200" || "$plex_status" == "302" || "$plex_status" == "301" ]]; then
    echo -e "  ${GREEN}OK${NC}  Plex (http://localhost:32400/web)"
    ((PASS++))
else
    echo -e "  ${YELLOW}SKIP${NC}  Plex not detected (install separately, see SETUP.md)"
fi

echo ""
echo "=============================="
echo "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "Something's not right. Check the FAIL items above."
    echo "Most common fix: restart Docker Desktop and wait 30 seconds."
    exit 1
else
    echo "Everything looks good!"
fi
