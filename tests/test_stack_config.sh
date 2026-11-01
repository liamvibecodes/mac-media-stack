#!/bin/bash
# shellcheck source=tests/lib.sh
source "$(dirname "$0")/lib.sh"
# shellcheck source=scripts/lib/stack-config.sh
source "$REPO_DIR/scripts/lib/stack-config.sh"

# --- config_get ---
use_env "$(printf 'A=1\nQUOTED="two words"\nSINGLE=%sx y%s\nDUP=first\nDUP=second\nEMPTY=\n' "'" "'")"
assert_eq "1" "$(config_get A)" "reads a value"
assert_eq "two words" "$(config_get QUOTED)" "strips double quotes"
assert_eq "x y" "$(config_get SINGLE)" "strips single quotes"
assert_eq "first" "$(config_get DUP)" "first occurrence wins"
assert_eq "fallback" "$(config_get MISSING fallback)" "default for missing key"
assert_eq "fallback" "$(config_get EMPTY fallback)" "default for empty value"
assert_eq "" "$(config_get MISSING)" "empty when missing and no default"

rm -f "$STACK_ENV_FILE"
assert_eq "d" "$(config_get ANYTHING d)" "default when .env is absent"

# --- config_get_path ---
use_env $'CONFIG_DIR=~/cfg\n'
assert_eq "$HOME/cfg" "$(config_get_path CONFIG_DIR)" "expands leading ~"

# --- config_set ---
use_env $'A=1\nB=2\nB=3\nC=4\n'
config_set B new
assert_eq $'A=1\nB=new\nC=4' "$(cat "$STACK_ENV_FILE")" "replaces in place and drops duplicates"
config_set D added
assert_eq "added" "$(config_get D)" "appends missing key"
config_set KEY 'a&b|c\d/e=f'
assert_eq 'a&b|c\d/e=f' "$(config_get KEY)" "values with sed/awk metacharacters survive"
use_env 'NOTRAILINGNEWLINE=1'
config_set X 2
assert_eq $'NOTRAILINGNEWLINE=1\nX=2' "$(cat "$STACK_ENV_FILE")" "appends after a file without trailing newline"
rm -f "$STACK_ENV_FILE"
config_set NEW 1
assert_eq "1" "$(config_get NEW)" "creates .env when absent"
use_env $'A=1\n'
chmod 600 "$STACK_ENV_FILE"
config_set A 2
assert_eq "600" "$(stat -c %a "$STACK_ENV_FILE" 2>/dev/null || stat -f %Lp "$STACK_ENV_FILE")" "keeps file mode"

# --- config_unset ---
use_env $'A=1\nB=2\n#B=commented\n'
config_unset B
assert_eq $'A=1\n#B=commented' "$(cat "$STACK_ENV_FILE")" "removes active key only"

# --- derived options ---
use_env ''
assert_eq "media.lan" "$(stack_proxy_domain)" "proxy domain default"
assert_fails "proxy off by default" stack_proxy_enabled
use_env $'COMPOSE_FILE=docker-compose.yml:docker-compose.proxy.yml\nPROXY_DOMAIN="home.lan"\n'
assert_ok "proxy on when its file is in COMPOSE_FILE" stack_proxy_enabled
assert_eq "home.lan" "$(stack_proxy_domain)" "proxy domain from .env"

# --- stack_media_dir ---
use_env $'MEDIA_DIR="~/Movies"\n'
assert_eq "$HOME/Movies" "$(MEDIA_DIR='' stack_media_dir)" ".env value, ~ expanded"
assert_eq "/x/y" "$(MEDIA_DIR=/x/y stack_media_dir)" "env var beats .env"
use_env ''
assert_eq "$HOME/Media" "$(MEDIA_DIR='' stack_media_dir)" "falls back to ~/Media"

# --- stack_compose_files ---
assert_eq "docker-compose.yml" "$(stack_compose_files false)" "default compose files"
assert_eq "docker-compose.yml:docker-compose.proxy.yml" "$(stack_compose_files true)" "proxy override"

# --- stack_apply_choices ---
use_env ''
stack_apply_choices true
assert_eq "docker-compose.yml:docker-compose.proxy.yml" "$(config_get COMPOSE_FILE)" "apply: compose files"
assert_eq "media.lan" "$(config_get PROXY_DOMAIN)" "apply: proxy domain defaulted"
stack_apply_choices true
assert_eq "1" "$(grep -c '^COMPOSE_FILE=' "$STACK_ENV_FILE")" "apply is idempotent (one COMPOSE_FILE)"
stack_apply_choices false
assert_eq "" "$(config_get COMPOSE_FILE)" "apply: proxy off removes COMPOSE_FILE"
use_env $'COMPOSE_FILE=custom.yml\nPROXY_DOMAIN=mine.lan\n'
stack_apply_choices false
assert_eq "custom.yml" "$(config_get COMPOSE_FILE)" "apply: leaves unrelated COMPOSE_FILE alone"
stack_apply_choices true
assert_eq "mine.lan" "$(config_get PROXY_DOMAIN)" "apply: keeps existing PROXY_DOMAIN"

finish
