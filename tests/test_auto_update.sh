#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# End to end: a throwaway copy of the scripts, with fake docker/curl on PATH that
# record what auto-update.sh asks of them and a stub refresh-image-lock.sh.
PROJECT="$T_TMP/project"
FAKE_BIN="$T_TMP/bin"
export AUTO_UPDATE_LOG_DIR="$T_TMP/logs"
export FAKE_DOCKER_LOG="$T_TMP/docker.log"
LOG="$AUTO_UPDATE_LOG_DIR/auto-update.log"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/docker" <<'EOF'
#!/bin/bash
echo "$*" >> "$FAKE_DOCKER_LOG"
case "$1 $2" in
    "info "*) [[ "${FAKE_DOCKER_DOWN:-}" == 1 ]] && exit 1 ;;
    "compose config")
        if [[ "${FAKE_IMAGE_CHANGES:-}" == 1 && -f "$FAKE_DOCKER_LOG.refreshed" ]]; then echo img:new
        else echo img:old; fi ;;
    "compose images")
        if [[ "${FAKE_IMAGE_CHANGES:-}" != 1 ]]; then echo same
        elif [[ -f "$FAKE_DOCKER_LOG.up" ]]; then echo new
        else echo old; fi ;;
    "compose up") touch "$FAKE_DOCKER_LOG.up"; [[ "${FAKE_UP_FAILS:-}" == 1 ]] && exit 1 ;;
esac
exit 0
EOF
printf '#!/bin/bash\necho 200\n' > "$FAKE_BIN/curl"
chmod +x "$FAKE_BIN/docker" "$FAKE_BIN/curl"

mkdir -p "$PROJECT/scripts"
cp -R "$REPO_DIR/scripts/." "$PROJECT/scripts/"
cp "$REPO_DIR/.env.example" "$PROJECT/"

# Stand-in for the real refresh, which pulls every image and rewrites the compose files.
cat > "$PROJECT/scripts/refresh-image-lock.sh" <<'EOF'
#!/bin/bash
echo "refresh-image-lock" >> "$FAKE_DOCKER_LOG"
[[ "${FAKE_REFRESH_FAILS:-}" == 1 ]] && exit 1
touch "$FAKE_DOCKER_LOG.refreshed"
printf '\033[32mRefreshing sonarr\033[0m\n'
EOF

run_update() { env "$@" HOME="$T_TMP/home" PATH="$FAKE_BIN:$PATH" bash "$PROJECT/scripts/auto-update.sh"; }
reset_calls() { rm -f "$FAKE_DOCKER_LOG" "$FAKE_DOCKER_LOG".*; }

# --- every image already current ---
assert_ok "runs when current" run_update
assert_ok "refreshes the images" grep -qx "refresh-image-lock" "$FAKE_DOCKER_LOG"
assert_ok "reports already current" grep -q "Images already up to date" "$LOG"
assert_ok "still reconciles containers" grep -q "^compose up -d --remove-orphans" "$FAKE_DOCKER_LOG"
assert_fails "keeps the up-to-date image" grep -q "^rmi" "$FAKE_DOCKER_LOG"

# --- newer images are published ---
reset_calls
assert_ok "runs when images changed" run_update FAKE_IMAGE_CHANGES=1
assert_ok "logs the new image" grep -q "New images: img:new" "$LOG"
assert_ok "removes the replaced image" grep -qx "rmi old" "$FAKE_DOCKER_LOG"
assert_ok "reports a healthy stack" grep -q "OK: Stack is up" "$LOG"
assert_fails "log has no colour codes" grep -q $'\x1b' "$LOG"

# --- refresh failing ---
reset_calls
assert_fails "stops when the refresh fails" run_update FAKE_REFRESH_FAILS=1
assert_ok "logs why" grep -q "Could not refresh the images" "$LOG"
assert_fails "leaves containers alone" test -f "$FAKE_DOCKER_LOG.up"

# --- runtime not running / compose failing ---
reset_calls
assert_fails "stops when the runtime is down" run_update FAKE_DOCKER_DOWN=1
assert_ok "logs the runtime error" grep -q "Container runtime not running" "$LOG"
assert_fails "stops when compose up fails" run_update FAKE_UP_FAILS=1
assert_ok "logs the compose error" grep -q "docker compose up failed" "$LOG"

finish
