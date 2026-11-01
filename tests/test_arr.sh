#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/arr.sh
source "$REPO_DIR/scripts/lib/arr.sh"

# Recording adapter for the HTTP seam. FAKE_CODE/FAKE_BODY set the response.
CALLS="$T_TMP/calls"
api_http_post() {
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" | tr '\n' ' ' >> "$CALLS"
    echo >> "$CALLS"
    echo "${FAKE_CODE:-201}"
    echo "${FAKE_BODY:-{\}}"
}
valid_json() { python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$1" 2>/dev/null; }
have_python() { command -v python3 >/dev/null 2>&1; }

use_env ''
: > "$CALLS"
assert_ok "radarr" arr_configure_app radarr KEY1 >/dev/null
assert_eq "3" "$(wc -l < "$CALLS" | tr -d ' ')" "root folder + client + path mapping"
assert_ok "root folder url+key" grep -q 'http://localhost:7878/api/v3/rootfolder	KEY1	{"path": "/data/movies", "accessible": true}' "$CALLS"
assert_ok "download client url" grep -q 'http://localhost:7878/api/v3/downloadclient	KEY1	' "$CALLS"
assert_ok "rtorrent implementation" grep -q '"implementation": "RTorrent"' "$CALLS"
assert_ok "radarr field names" grep -q '"name": "movieCategory", "value": "radarr"' "$CALLS"
assert_ok "radarr priority fields" grep -q 'recentMoviePriority", "value": 2' "$CALLS"
assert_ok "path mapping" grep -q 'remotepathmapping	KEY1	{"host": "gluetun", "remotePath": "/downloads/"' "$CALLS"
assert_fails "no password in payload" grep -q '"name": "password"' "$CALLS"

: > "$CALLS"
arr_configure_app sonarr KEY2 >/dev/null
assert_ok "sonarr root folder" grep -q '{"path": "/data/tvshows", "accessible": true}' "$CALLS"
assert_ok "sonarr url" grep -q 'http://localhost:8989/api/v3/downloadclient	KEY2' "$CALLS"
assert_ok "sonarr field names" grep -q '"name": "tvCategory", "value": "tv-sonarr"' "$CALLS"
assert_ok "sonarr priority fields" grep -q 'recentTvPriority", "value": 2' "$CALLS"

if have_python; then
    payload="$(_arr_profile radarr; _arr_download_client_payload)"
    assert_ok "radarr payload is valid JSON" valid_json "$payload"
    payload="$(_arr_profile sonarr; _arr_download_client_payload)"
    assert_ok "sonarr payload is valid JSON" valid_json "$payload"
fi

# error handling
: > "$CALLS"
FAKE_CODE=500 FAKE_BODY=boom
assert_fails "http 500 fails" arr_configure_app radarr K >/dev/null 2>&1
assert_eq "1" "$(wc -l < "$CALLS" | tr -d ' ')" "stops at first failure"

: > "$CALLS"
FAKE_CODE=400 FAKE_BODY='{"errorMessage":"Path already exists"}'
assert_ok "'already exists' is treated as success" arr_configure_app radarr K >/dev/null
assert_eq "3" "$(wc -l < "$CALLS" | tr -d ' ')" "continues after already-exists"

assert_fails "unknown app" arr_configure_app lidarr K >/dev/null 2>&1

finish
