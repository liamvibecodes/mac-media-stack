#!/bin/bash
# Radarr/Sonarr (and other *arr / Seerr) API operations for configure.sh.
#
# Interface
#   api_post_json LABEL URL API_KEY PAYLOAD
#       POST JSON; "already exists" counts as success. Returns 1 on failure.
#   arr_configure_app APP API_KEY
#       APP is radarr|sonarr. Adds the root folder, the rTorrent download
#       client and the path mapping it needs. Stops at the first failure.
#
# Seam: every HTTP request goes through `api_http_post URL API_KEY PAYLOAD`,
# which prints the status code on the first line and the response body after it.
# The default adapter uses curl; tests redefine the function.
#
# Needs: ui.sh and topology.sh (for the base URLs).

_ARR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/topology.sh
source "$_ARR_DIR/topology.sh"

api_http_post() {
    local url="$1" api_key="$2" payload="$3" body_file http_code
    body_file="$(mktemp)"
    http_code=$(curl -sS -o "$body_file" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $api_key" \
        -d "$payload" "$url" || echo "000")
    echo "$http_code"
    cat "$body_file"
    rm -f "$body_file"
}

api_post_json() {
    local label="$1" url="$2" api_key="$3" payload="$4"
    local response http_code body

    response="$(api_http_post "$url" "$api_key" "$payload")"
    http_code="${response%%$'\n'*}"
    body="${response#"$http_code"}"

    if [[ "$http_code" =~ ^2 ]]; then
        ui_ok "$label"
        return 0
    fi

    if grep -qiE "already exists|already configured|must be unique|should be unique|duplicate" <<<"$body"; then
        ui_info "$label (already configured)"
        return 0
    fi

    ui_fail "$label (HTTP $http_code)"
    sed -n '1,2p' <<<"${body#$'\n'}" >&2 || true
    return 1
}

# Sets the per-app facts: name, URL, media category, field names, root folder.
_arr_profile() {
    case "$1" in
        radarr)
            ARR_NAME=Radarr
            ARR_CATEGORY=radarr
            ARR_CATEGORY_FIELD=movieCategory
            ARR_RECENT_FIELD=recentMoviePriority
            ARR_OLDER_FIELD=olderMoviePriority
            ARR_ROOT_PATH=/data/movies
            ;;
        sonarr)
            ARR_NAME=Sonarr
            ARR_CATEGORY=tv-sonarr
            ARR_CATEGORY_FIELD=tvCategory
            ARR_RECENT_FIELD=recentTvPriority
            ARR_OLDER_FIELD=olderTvPriority
            ARR_ROOT_PATH=/data/tvshows
            ;;
        *)
            echo "arr: unknown app '$1'" >&2
            return 1
            ;;
    esac
    ARR_URL="$(topology_url "$1")"
}

_arr_download_client_payload() {
    cat <<JSON
{"enable": true, "protocol": "torrent", "name": "rTorrent",
 "implementation": "RTorrent", "configContract": "RTorrentSettings",
 "priority": 1,
 "fields": [
  {"name": "host", "value": "gluetun"},
  {"name": "port", "value": 8000},
  {"name": "useSsl", "value": false},
  {"name": "urlBase", "value": "RPC2"},
  {"name": "$ARR_CATEGORY_FIELD", "value": "$ARR_CATEGORY"},
  {"name": "$ARR_RECENT_FIELD", "value": 2},
  {"name": "$ARR_OLDER_FIELD", "value": 2},
  {"name": "addStopped", "value": false}],
 "removeCompletedDownloads": false, "removeFailedDownloads": true}
JSON
}

arr_configure_app() {
    local app="$1" api_key="$2"

    _arr_profile "$app" || return 1

    api_post_json "$ARR_NAME root folder set to $ARR_ROOT_PATH" \
        "$ARR_URL/api/v3/rootfolder" "$api_key" \
        "{\"path\": \"$ARR_ROOT_PATH\", \"accessible\": true}" || return 1

    api_post_json "$ARR_NAME download client configured (rTorrent)" \
        "$ARR_URL/api/v3/downloadclient" "$api_key" \
        "$(_arr_download_client_payload)" || return 1

    # rTorrent sees downloads at /downloads, the *arr apps see the same folder at /data/downloads
    api_post_json "$ARR_NAME path mapping: /downloads/ -> /data/downloads/" \
        "$ARR_URL/api/v3/remotepathmapping" "$api_key" \
        '{"host": "gluetun", "remotePath": "/downloads/", "localPath": "/data/downloads/"}' || return 1
    return 0
}
