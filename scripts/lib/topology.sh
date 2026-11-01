#!/bin/bash
# Stack topology: which containers and web UIs make up the stack for the
# current configuration (Emby, rTorrent + Flood, optional proxy). Health checks,
# the auto-healer, preflight and the installer iterate this instead of keeping
# their own lists.
#
# Interface
#   topology_entries         one line per member: container|label|probe-url|probe
#                            probe-url is empty when there is no web UI (gluetun),
#                            probe is "required" (health FAIL if down) or "advisory"
#   topology_containers      container names, one per line
#   topology_ports           host ports to be free before first start, one per line
#   topology_url NAME        base URL of a container, whatever the current choices
#   topology_port NAME       port of that URL
#   topology_wait_ready [ATTEMPTS] [LEVEL]   wait for every Docker web UI;
#                            fails only if a required one never answers
#
# Needs: stack-config.sh and ui.sh (sourced below).

_TOPOLOGY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/stack-config.sh
source "$_TOPOLOGY_DIR/stack-config.sh"
# shellcheck source=scripts/lib/ui.sh
source "$_TOPOLOGY_DIR/ui.sh"

# when|container|label|base-url|probe-path|probe
_topology_table() {
    cat <<'TABLE'
always|gluetun|VPN gateway|||required
always|rtorrent|ruTorrent|http://localhost:8080||required
always|flood|Flood|http://localhost:3000||required
proxy|caddy|Caddy|||required
always|prowlarr|Prowlarr|http://localhost:9696||required
always|sonarr|Sonarr|http://localhost:8989||required
always|radarr|Radarr|http://localhost:7878||required
always|bazarr|Bazarr|http://localhost:6767||required
always|flaresolverr|FlareSolverr|http://localhost:8191||required
always|seerr|Seerr|http://localhost:5055||required
always|emby|Emby|http://localhost:8096|/emby/System/Ping|advisory
TABLE
}

topology_entries() {
    local proxy=false
    local when container label base path probe

    if stack_proxy_enabled; then proxy=true; fi

    while IFS='|' read -r when container label base path probe; do
        case "$when" in
            always) ;;
            proxy) [[ "$proxy" == true ]] || continue ;;
        esac
        if [[ -n "$base" ]]; then
            printf '%s|%s|%s%s|%s\n' "$container" "$label" "$base" "$path" "$probe"
        else
            printf '%s|%s||%s\n' "$container" "$label" "$probe"
        fi
    done < <(_topology_table)
}

topology_containers() {
    local container label url probe
    while IFS='|' read -r container label url probe; do
        [[ -n "$container" ]] && printf '%s\n' "$container"
    done < <(topology_entries)
    return 0
}

topology_url() {
    local want="$1" when container label base rest
    while IFS='|' read -r when container label base rest; do
        label="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        if [[ "$container" == "$want" || "$label" == "$want" ]]; then
            printf '%s\n' "$base"
            return 0
        fi
    done < <(_topology_table)
    return 1
}

# http://host:PORT/path -> PORT
_topology_url_port() {
    local url="${1#*://}"
    url="${url#*:}"
    printf '%s\n' "${url%%/*}"
}

topology_port() {
    local url
    url="$(topology_url "$1")" || return 1
    _topology_url_port "$url"
}

topology_ports() {
    local container label url probe
    {
        while IFS='|' read -r container label url probe; do
            [[ -n "$url" ]] || continue
            _topology_url_port "$url"
        done < <(topology_entries)
        if stack_proxy_enabled; then echo 80; fi
    } | sort -un
}

topology_wait_ready() {
    local attempts="${1:-45}" level="${2:-warn}" rc=0
    local container label url probe
    while IFS='|' read -r container label url probe; do
        [[ -n "$container" && -n "$url" ]] || continue
        if [[ "$probe" == "required" ]]; then
            wait_for_service "$label" "$url" "$attempts" "$level" || rc=1
        else
            wait_for_service "$label" "$url" "$attempts" warn || true
        fi
    done < <(topology_entries)
    return $rc
}
