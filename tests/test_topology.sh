#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/topology.sh
source "$REPO_DIR/scripts/lib/topology.sh"

names() { topology_containers | tr '\n' ' ' | sed 's/ $//'; }

use_env ''
assert_eq "gluetun rtorrent flood prowlarr sonarr radarr bazarr flaresolverr seerr emby" "$(names)" "default stack: rtorrent + emby"
assert_eq "emby|Emby|http://localhost:8096/emby/System/Ping|advisory" "$(topology_entries | grep '^emby')" "emby probe"

use_env $'COMPOSE_FILE=docker-compose.yml:docker-compose.proxy.yml\n'
assert_eq "gluetun rtorrent flood caddy prowlarr sonarr radarr bazarr flaresolverr seerr emby" "$(names)" "proxy adds caddy"
assert_eq "caddy|Caddy||required" "$(topology_entries | grep '^caddy')" "caddy has no web probe"

# ports
use_env ''
assert_eq "3000 5055 6767 7878 8080 8096 8191 8989 9696" "$(topology_ports | tr '\n' ' ' | sed 's/ $//')" "default ports"
use_env $'COMPOSE_FILE=docker-compose.yml:docker-compose.proxy.yml\n'
assert_eq "80 3000 5055 6767 7878 8080 8096 8191 8989 9696" "$(topology_ports | sort -n | tr '\n' ' ' | sed 's/ $//')" "ports with proxy"

# url lookup works regardless of current choices
use_env ''
assert_eq "http://localhost:7878" "$(topology_url radarr)" "topology_url radarr"
assert_eq "http://localhost:3000" "$(topology_url flood)" "topology_url flood"
assert_eq "http://localhost:8096" "$(topology_url emby)" "topology_url emby"
assert_eq "5055" "$(topology_port seerr)" "topology_port seerr"
assert_fails "unknown name" topology_url nope
assert_fails "removed qbittorrent is unknown" topology_url qbittorrent

# shellcheck disable=SC2329  # replaces the real function; called by topology_wait_ready
# wait: required failure => nonzero; advisory failure => ok. Fake wait_for_service.
wait_for_service() { echo "$1|$4" >> "$T_TMP/waited"; [[ "$1" != "Radarr" && "$1" != "Emby" ]]; }
use_env ''
: > "$T_TMP/waited"
assert_fails "required service down => failure" topology_wait_ready 1 fail
assert_ok "all waited, advisory uses warn" grep -q '^Emby|warn$' "$T_TMP/waited"
assert_ok "required uses requested level" grep -q '^Seerr|fail$' "$T_TMP/waited"
assert_fails "gluetun (no url) not waited" grep -q 'VPN gateway' "$T_TMP/waited"
wait_for_service() { return 0; }
assert_ok "all up => success" topology_wait_ready 1 fail

finish
