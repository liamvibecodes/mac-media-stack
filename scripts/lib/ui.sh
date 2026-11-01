#!/bin/bash
# Shared terminal output and the "wait until a web UI answers" loop.
#
# Interface
#   RED GREEN YELLOW CYAN NC          colour codes
#   ui_ok|ui_warn|ui_fail|ui_info|ui_skip MSG   one status line each (OK / WARN / FAIL / .. / SKIP)
#   wait_for_service NAME URL [ATTEMPTS=45] [LEVEL=warn|fail]
#       polls every 2s; returns 0 once the URL answers, 1 on timeout
#       (reported as WARN "continuing anyway", or FAIL when LEVEL=fail)

# Colours are consumed by the scripts that source this file.
# shellcheck disable=SC2034
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

_ui_line() {
    local colour="$1" label="$2" msg="$3"
    echo -e "  ${colour}$(printf '%-4s' "$label")${NC}  $msg"
}

ui_ok() { _ui_line "$GREEN" "OK" "$1"; }
ui_warn() { _ui_line "$YELLOW" "WARN" "$1"; }
ui_fail() { _ui_line "$RED" "FAIL" "$1"; }
ui_info() { _ui_line "$YELLOW" ".." "$1"; }
ui_skip() { _ui_line "$YELLOW" "SKIP" "$1"; }

wait_for_service() {
    local name="$1" url="$2" max_attempts="${3:-45}" level="${4:-warn}"
    local attempt=0 status

    while [[ $attempt -lt $max_attempts ]]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true)
        if [[ "$status" =~ ^(200|301|302|401|403)$ ]]; then
            ui_ok "$name is reachable"
            return 0
        fi
        [[ $attempt -eq 0 ]] && ui_info "Waiting for $name..."
        sleep 2
        attempt=$((attempt + 1))
    done

    if [[ "$level" == "fail" ]]; then
        ui_fail "$name didn't start after $((max_attempts * 2)) seconds"
    else
        ui_warn "$name is not reachable yet (continuing anyway)"
    fi
    return 1
}
