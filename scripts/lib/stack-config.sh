#!/bin/bash
# Stack configuration: the one module that reads and writes .env and decides
# which compose files and options are active. Scripts ask questions here
# instead of parsing .env themselves.
#
# Interface
#   config_get KEY [DEFAULT]        value from .env (surrounding quotes removed)
#   config_get_path KEY [DEFAULT]   same, with a leading ~ expanded
#   config_set KEY VALUE            replace KEY in place, or append it
#   config_unset KEY                remove KEY
#   stack_media_dir                 $MEDIA_DIR env var -> .env -> ~/Media
#   stack_proxy_enabled             exit 0 when the Caddy proxy file is loaded
#   stack_proxy_domain              hostname suffix for the proxy (default media.lan)
#   stack_compose_files PROXY       colon-joined COMPOSE_FILE value
#   stack_apply_choices PROXY       write the install-time choices
#
# The file read is $STACK_ENV_FILE, otherwise <project>/.env.
# Compatible with bash 3.2 (macOS system bash).

_STACK_PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

stack_env_file() {
    printf '%s\n' "${STACK_ENV_FILE:-$_STACK_PROJECT_DIR/.env}"
}

config_get() {
    local key="$1" default="${2:-}" file value=""
    file="$(stack_env_file)"
    if [[ -f "$file" ]]; then
        value="$(sed -n "/^${key}=/{s/^${key}=//p;q;}" "$file" || true)"
    fi
    value="${value%\"}"
    value="${value#\"}"
    value="${value%\'}"
    value="${value#\'}"
    printf '%s\n' "${value:-$default}"
}

config_get_path() {
    local value
    value="$(config_get "$@")"
    printf '%s\n' "${value/#\~/$HOME}"
}

# Replaces the first KEY= line (dropping any duplicates) or appends a new one.
# The value goes through the environment so it is never interpreted by sed/awk.
config_set() {
    local key="$1" value="$2" file tmp
    file="$(stack_env_file)"
    [[ -f "$file" ]] || : > "$file"
    tmp="$(mktemp)"
    CONFIG_KEY="$key" CONFIG_VALUE="$value" awk '
        BEGIN { prefix = ENVIRON["CONFIG_KEY"] "="; line = prefix ENVIRON["CONFIG_VALUE"]; done = 0 }
        index($0, prefix) == 1 { if (!done) { print line; done = 1 } ; next }
        { print }
        END { if (!done) print line }
    ' "$file" > "$tmp"
    # cat (not mv) keeps the file's existing mode, e.g. chmod 600
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

config_unset() {
    local key="$1" file tmp
    file="$(stack_env_file)"
    [[ -f "$file" ]] || return 0
    tmp="$(mktemp)"
    CONFIG_KEY="$key" awk 'index($0, ENVIRON["CONFIG_KEY"] "=") != 1 { print }' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

stack_media_dir() {
    local value="${MEDIA_DIR:-}"
    [[ -n "$value" ]] || value="$(config_get MEDIA_DIR)"
    value="${value:-$HOME/Media}"
    printf '%s\n' "${value/#\~/$HOME}"
}

stack_proxy_enabled() {
    [[ "$(config_get COMPOSE_FILE)" == *docker-compose.proxy.yml* ]]
}

stack_proxy_domain() { config_get PROXY_DOMAIN media.lan; }

stack_compose_files() {
    local proxy="$1" files="docker-compose.yml"
    [[ "$proxy" == "true" ]] && files+=":docker-compose.proxy.yml"
    printf '%s\n' "$files"
}

# Records the choices made at install time. Docker Compose itself reads
# COMPOSE_FILE from .env, so the optional override file is listed there.
stack_apply_choices() {
    local proxy="$1" files current
    files="$(stack_compose_files "$proxy")"

    if [[ "$proxy" == "true" && -z "$(config_get PROXY_DOMAIN)" ]]; then
        config_set PROXY_DOMAIN media.lan
    fi

    current="$(config_get COMPOSE_FILE)"
    if [[ "$files" != "docker-compose.yml" ]]; then
        config_set COMPOSE_FILE "$files"
    elif [[ "$current" == *docker-compose.proxy.yml* ]]; then
        config_unset COMPOSE_FILE
    fi
}
