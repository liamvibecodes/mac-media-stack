#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/vpn.sh
source "$REPO_DIR/scripts/lib/vpn.sh"

# Fake docker: behaviour driven by FAKE_IP / FAKE_IFACE / FAKE_HEALTH.
docker() {
    case "$1" in
        exec)
            case "$5" in
                *gluetun/ip*) printf '%s' "${FAKE_IP:-}" ;;
                *) printf '%s' "${FAKE_IFACE:-}" ;;
            esac ;;
        inspect) printf '%s' "${FAKE_HEALTH:-}" ;;
    esac
}

FAKE_IP=1.2.3.4 FAKE_IFACE=tun0 FAKE_HEALTH=healthy
assert_ok "healthy tunnel" vpn_probe
assert_eq "ok 1.2.3.4 tun0 healthy" "$VPN_STATE $VPN_IP $VPN_IFACE $VPN_HEALTH" "healthy fields"

FAKE_HEALTH=""
assert_ok "health unknown still ok" vpn_probe
assert_eq "unknown" "$VPN_HEALTH" "missing health reported as unknown"

FAKE_HEALTH=unhealthy
assert_fails "unhealthy" vpn_probe
assert_eq "unhealthy" "$VPN_STATE" "state unhealthy"

FAKE_IFACE="" FAKE_HEALTH=healthy
assert_fails "no interface" vpn_probe
assert_eq "no-iface" "$VPN_STATE" "state no-iface"

FAKE_IP="" FAKE_IFACE=tun0
assert_fails "no ip" vpn_probe
assert_eq "no-ip" "$VPN_STATE" "state no-ip"

finish
