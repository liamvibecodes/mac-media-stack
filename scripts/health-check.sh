#!/bin/bash
# Media Stack Health Check
# Run this anytime to check if everything is working.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/runtime.sh
source "$SCRIPT_DIR/scripts/lib/runtime.sh"
# shellcheck source=scripts/lib/topology.sh
source "$SCRIPT_DIR/scripts/lib/topology.sh"
# shellcheck source=scripts/lib/vpn.sh
source "$SCRIPT_DIR/scripts/lib/vpn.sh"

echo ""
echo "=============================="
echo "  Media Stack Health Check"
echo "=============================="
echo ""

PASS=0
FAIL=0

pass() { ui_ok "$1"; PASS=$((PASS + 1)); }
flunk() { ui_fail "$1"; FAIL=$((FAIL + 1)); }

http_status() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$1" 2>/dev/null
}

reachable() {
    [[ "$(http_status "$1")" =~ ^(200|301|302)$ ]]
}

check_service() {
    local name="$1" url="$2" status
    status="$(http_status "$url")"
    if [[ "$status" =~ ^(200|301|302)$ ]]; then
        pass "$name"
    else
        flunk "$name (got HTTP $status)"
    fi
}

RUNTIME=$(detect_installed_runtime)

if docker info &>/dev/null; then
    RUNTIME=$(detect_running_runtime)
    pass "$RUNTIME"
else
    flunk "$RUNTIME (not running)"
    echo ""
    echo "Start $RUNTIME and try again."
    exit 1
fi

echo ""

# Check containers are running
echo "Containers:"
while IFS='|' read -r container label url probe; do
    [[ -n "$container" ]] || continue
    state=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
    if [[ "$state" == "running" ]]; then
        pass "$container"
    else
        flunk "$container (${state:-not found})"
    fi
done < <(topology_entries)

watchtower_state=$(docker inspect -f '{{.State.Status}}' watchtower 2>/dev/null || true)
if [[ "$watchtower_state" == "running" ]]; then
    pass "watchtower (autoupdate profile enabled)"
else
    ui_skip "watchtower (optional; enable with --profile autoupdate)"
fi

echo ""
echo "Web UIs:"
while IFS='|' read -r container label url probe; do
    [[ -n "$url" && "$probe" == "required" ]] || continue
    check_service "$label" "$url"
done < <(topology_entries)

echo ""
echo "VPN:"
if vpn_probe; then
    pass "VPN active (IP: $VPN_IP, iface: $VPN_IFACE, health: $VPN_HEALTH)"
else
    case "$VPN_STATE" in
        no-ip) flunk "VPN not connected (missing /tmp/gluetun/ip)" ;;
        no-iface) flunk "VPN tunnel interface not detected in gluetun" ;;
        *) flunk "VPN health is unhealthy" ;;
    esac
fi

# Emby: advisory, since it may still be starting
while IFS='|' read -r container label url probe; do
    [[ -n "$url" && "$probe" == "advisory" ]] || continue
    echo ""
    echo "$label:"
    if reachable "$url"; then
        pass "$label ($url)"
    else
        ui_skip "$label not reachable yet (may still be starting)"
    fi
done < <(topology_entries)

echo ""
echo "=============================="
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "Something's not right. Check the FAIL items above."
    echo "Most common fix: restart your container runtime (OrbStack or Docker Desktop) and wait 30 seconds."
    exit 1
else
    echo "Everything looks good!"
fi
