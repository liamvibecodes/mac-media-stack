#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"

# End to end: a throwaway origin with release tags, a clone of it, and fake
# docker/curl on PATH that record what auto-update.sh asks of them.
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

ORIGIN="$T_TMP/origin"
CLONE="$T_TMP/clone"
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

mkdir "$ORIGIN"
git -C "$ORIGIN" init -q -b main
mkdir -p "$ORIGIN/scripts"
cp -R "$REPO_DIR/scripts/." "$ORIGIN/scripts/"
cp "$REPO_DIR/.env.example" "$ORIGIN/"
git -C "$ORIGIN" add -A
git -C "$ORIGIN" commit -q -m one
git -C "$ORIGIN" tag v1.0.0
git clone -q "$ORIGIN" "$CLONE"

run_update() { HOME="$T_TMP/home" PATH="$FAKE_BIN:$PATH" bash "$CLONE/scripts/auto-update.sh"; }
reset_calls() { rm -f "$FAKE_DOCKER_LOG" "$FAKE_DOCKER_LOG.up"; }

# --- already on the latest release ---
assert_ok "runs when current" run_update
assert_ok "reports already current" grep -q "Already on the latest release" "$LOG"
assert_ok "still reconciles containers" grep -q "^compose up -d --remove-orphans" "$FAKE_DOCKER_LOG"
assert_fails "keeps the up-to-date image" grep -q "^rmi" "$FAKE_DOCKER_LOG"

# --- a new release is published ---
echo two > "$ORIGIN/CHANGES"
git -C "$ORIGIN" add -A
git -C "$ORIGIN" commit -q -m two
git -C "$ORIGIN" tag v1.1.0
reset_calls
assert_ok "runs when a release is out" env FAKE_IMAGE_CHANGES=1 HOME="$T_TMP/home" PATH="$FAKE_BIN:$PATH" bash "$CLONE/scripts/auto-update.sh"
assert_eq "$(git -C "$ORIGIN" rev-parse v1.1.0)" "$(git -C "$CLONE" rev-parse HEAD)" "clone moved to the new tag"
assert_ok "logs the update" grep -q "Updated to v1.1.0" "$LOG"
assert_ok "removes the replaced image" grep -qx "rmi old" "$FAKE_DOCKER_LOG"
assert_ok "reports a healthy stack" grep -q "OK: Stack is up" "$LOG"
assert_fails "log has no colour codes" grep -q $'\x1b' "$LOG"

# --- local changes block the update ---
echo three > "$ORIGIN/CHANGES"
git -C "$ORIGIN" add -A
git -C "$ORIGIN" commit -q -m three
git -C "$ORIGIN" tag v1.2.0
echo local >> "$CLONE/CHANGES"
reset_calls
assert_fails "refuses with local changes" run_update
assert_ok "logs why" grep -q "Could not move to the latest release" "$LOG"
assert_fails "leaves containers alone" test -f "$FAKE_DOCKER_LOG.up"
git -C "$CLONE" checkout -q -- CHANGES

# --- runtime not running / compose failing ---
reset_calls
assert_fails "stops when the runtime is down" env FAKE_DOCKER_DOWN=1 HOME="$T_TMP/home" PATH="$FAKE_BIN:$PATH" bash "$CLONE/scripts/auto-update.sh"
assert_ok "logs the runtime error" grep -q "Container runtime not running" "$LOG"
assert_fails "stops when compose up fails" env FAKE_UP_FAILS=1 HOME="$T_TMP/home" PATH="$FAKE_BIN:$PATH" bash "$CLONE/scripts/auto-update.sh"
assert_ok "logs the compose error" grep -q "docker compose up failed" "$LOG"

finish
