#!/bin/bash
# VPN tunnel probe: asks the gluetun container whether the tunnel is up.
#
# Interface
#   vpn_probe    returns 0 when the tunnel is healthy and sets, for the caller:
#                  VPN_STATE   ok | no-ip | no-iface | unhealthy
#                  VPN_IP      public IP reported by gluetun (may be empty)
#                  VPN_IFACE   tunnel interface, tun0/wg0 (may be empty)
#                  VPN_HEALTH  Docker health status (healthy|unhealthy|starting|unknown)
#
# Needs the `docker` command; tests put a fake one on PATH.

VPN_CONTAINER=gluetun

vpn_probe() {
    VPN_IP="$(docker exec "$VPN_CONTAINER" sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null || true)"
    VPN_IFACE="$(docker exec "$VPN_CONTAINER" sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null || true)"
    VPN_HEALTH="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$VPN_CONTAINER" 2>/dev/null || true)"
    VPN_HEALTH="${VPN_HEALTH:-unknown}"

    if [[ -n "$VPN_IP" && -n "$VPN_IFACE" && "$VPN_HEALTH" != "unhealthy" ]]; then
        VPN_STATE=ok
    elif [[ -z "$VPN_IP" ]]; then
        VPN_STATE=no-ip
    elif [[ -z "$VPN_IFACE" ]]; then
        VPN_STATE=no-iface
    else
        VPN_STATE=unhealthy
    fi
    [[ "$VPN_STATE" == "ok" ]]
}
