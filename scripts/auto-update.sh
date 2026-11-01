#!/bin/bash
# Media Stack Auto-Update
# Runs daily via launchd. Moves the stack to the Image lock of the latest release
# and recreates the containers whose image changed. Does nothing when already current.

set -o pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/topology.sh
source "$PROJECT_DIR/scripts/lib/topology.sh"

# Local disk on purpose: the media share may be unmounted or read-only
LOG_DIR="${AUTO_UPDATE_LOG_DIR:-$HOME/Library/Logs/media-stack}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/auto-update.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }

log() { echo "$(timestamp) $1" >> "$LOG"; }

# Appends a command's output to the log, without terminal colour codes.
run_logged() { "$@" 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' >> "$LOG"; }

# Trim log to last 500 lines
if [[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 500 ]]; then
    tail -500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi

log "--- Auto-update started ---"

cd "$PROJECT_DIR" || exit 1

if ! docker info &>/dev/null; then
    log "ERROR: Container runtime not running. Cannot update."
    exit 1
fi

before="$(git rev-parse HEAD 2>/dev/null)"
if ! run_logged bash scripts/update-to-latest-release.sh --yes; then
    log "ERROR: Could not move to the latest release (see above). Stack left as it was."
    exit 1
fi
after="$(git rev-parse HEAD)"

if [[ "$before" == "$after" ]]; then
    log "Already on the latest release"
else
    log "Updated to $(git describe --tags --always)"
fi

# Images in use now; the ones the update replaces are removed afterwards.
old_images="$(docker compose images --quiet 2>/dev/null | sort -u)"

# Recreates only containers whose image or configuration changed, pulls images that
# are missing, and removes containers of services a release has dropped.
if ! run_logged docker compose up -d --remove-orphans; then
    log "ERROR: docker compose up failed. Run: docker compose up -d"
    exit 1
fi

new_images="$(docker compose images --quiet 2>/dev/null | sort -u)"
while IFS= read -r image; do
    [[ -n "$image" ]] || continue
    grep -qx "$image" <<<"$new_images" || docker rmi "$image" >/dev/null 2>&1 || true
done <<<"$old_images"

if topology_wait_ready 45 fail >/dev/null; then
    log "OK: Stack is up"
else
    log "WARN: Some services are not answering after the update. Run: bash scripts/health-check.sh"
    exit 1
fi
