#!/bin/bash
# Media Stack Auto-Configurator
# Run this ONCE after "docker compose up -d" to configure all services.
# Replaces manual Steps 8-10 from SETUP.md.
# Usage: bash scripts/configure.sh [--non-interactive] [--help]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/arr.sh
source "$SCRIPT_DIR/scripts/lib/arr.sh"
NON_INTERACTIVE=false

usage() {
    cat <<EOF
Usage: bash scripts/configure.sh [OPTIONS]

Options:
  --non-interactive   Skip interactive Seerr Emby login wiring
  --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Load configuration (read as data, never sourced: values may contain spaces)
if [[ ! -f "$(stack_env_file)" ]]; then
    echo -e "${RED}Error:${NC} .env file not found. Run setup.sh first."
    exit 1
fi
MEDIA_DIR="$(stack_media_dir)"
CONFIG_DIR="$(config_get_path CONFIG_DIR "$MEDIA_DIR/config")"

RADARR_URL="$(topology_url radarr)"
SONARR_URL="$(topology_url sonarr)"
PROWLARR_URL="$(topology_url prowlarr)"
SEERR_URL="$(topology_url seerr)"
RADARR_PORT="$(topology_port radarr)"
SONARR_PORT="$(topology_port sonarr)"
PROWLARR_PORT="$(topology_port prowlarr)"

CREDS_FILE="$MEDIA_DIR/state/first-run-credentials.txt"

# ============================================================
# Helper functions
# ============================================================

log() { ui_ok "$1"; }
warn() { ui_info "$1"; }
fail() { ui_fail "$1"; }

save_credentials() {
    mkdir -p "$(dirname "$CREDS_FILE")"
    cat > "$CREDS_FILE" <<EOF
# Media Stack first-run credentials
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
rTorrent: no login (Flood: $(topology_url flood), ruTorrent: $(topology_url rtorrent))
Radarr API Key: $RADARR_KEY
Sonarr API Key: $SONARR_KEY
Prowlarr API Key: $PROWLARR_KEY
EOF
    chmod 600 "$CREDS_FILE"
}

api_post_form() {
    local label="$1"
    local url="$2"
    local cookie="$3"
    shift 3

    if curl -fsS -b "$cookie" "$url" "$@" >/dev/null; then
        log "$label"
        return 0
    fi

    fail "$label"
    return 1
}

get_api_key() {
    local service="$1"
    local config_path="$CONFIG_DIR/$service/config.xml"
    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if [[ -f "$config_path" ]]; then
            local key=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$config_path" 2>/dev/null | sed 's/<[^>]*>//g')
            if [[ -n "$key" ]]; then
                echo "$key"
                return 0
            fi
        fi
        sleep 2
        ((attempt++))
    done
    fail "Could not read API key for $service"
    return 1
}

# ============================================================
# Start
# ============================================================

echo ""
echo "=============================="
echo "  Media Stack Configurator"
echo "=============================="
echo ""
echo "This will auto-configure all services. Takes about 2 minutes."
echo ""

# ============================================================
# 1. Wait for all services to be ready
# ============================================================

echo -e "${CYAN}[1/6] Waiting for services to start...${NC}"
echo ""

topology_wait_ready 30 fail

echo ""

# ============================================================
# 2. Extract API keys
# ============================================================

echo -e "${CYAN}[2/6] Reading API keys...${NC}"
echo ""

RADARR_KEY=$(get_api_key "radarr")
log "Radarr API key: ${RADARR_KEY:0:8}..."

SONARR_KEY=$(get_api_key "sonarr")
log "Sonarr API key: ${SONARR_KEY:0:8}..."

PROWLARR_KEY=$(get_api_key "prowlarr")
log "Prowlarr API key: ${PROWLARR_KEY:0:8}..."

echo ""

# ============================================================
# 3. Configure rTorrent
# ============================================================

echo -e "${CYAN}[3/6] Configuring rTorrent...${NC}"
echo ""
log "rTorrent needs no setup (labels and paths come from Radarr/Sonarr)"

save_credentials || warn "Could not write $CREDS_FILE (API keys are under Settings > General in each app). Continuing."

echo ""

# ============================================================
# 4. Configure Radarr & Sonarr
# ============================================================

echo -e "${CYAN}[4/6] Configuring Radarr & Sonarr...${NC}"
echo ""

arr_configure_app radarr "$RADARR_KEY"
arr_configure_app sonarr "$SONARR_KEY"

echo ""

# ============================================================
# 5. Configure Prowlarr
# ============================================================

echo -e "${CYAN}[5/6] Configuring Prowlarr...${NC}"
echo ""

# --- Create FlareSolverr tag (ID will be 1) ---
FLARE_TAG_ID=$(curl -fsS "$PROWLARR_URL/api/v1/tag" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"label": "flaresolverr"}' | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
FLARE_TAG_ID="${FLARE_TAG_ID:-1}"
log "FlareSolverr tag created (ID: $FLARE_TAG_ID)"

# --- Add FlareSolverr indexer proxy ---
api_post_json "FlareSolverr proxy added" \
    "$PROWLARR_URL/api/v1/indexerProxy" \
    "$PROWLARR_KEY" \
    "{
        \"name\": \"FlareSolverr\",
        \"implementation\": \"FlareSolverr\",
        \"configContract\": \"FlareSolverrSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"http://flaresolverr:8191\"},
            {\"name\": \"requestTimeout\", \"value\": 60}
        ],
        \"tags\": [$FLARE_TAG_ID]
    }"

# --- Add indexers ---

# Cardigann-based indexers use a different format
add_cardigann_indexer() {
    local name="$1"
    local definition_name="$2"
    local base_url="$3"
    local tags="$4"

    api_post_json "Indexer added: $name" \
        "$PROWLARR_URL/api/v1/indexer" \
        "$PROWLARR_KEY" \
        "{
            \"name\": \"$name\",
            \"implementation\": \"Cardigann\",
            \"configContract\": \"CardigannSettings\",
            \"protocol\": \"torrent\",
            \"enable\": true,
            \"appProfileId\": 1,
            \"priority\": 25,
            \"fields\": [
                {\"name\": \"definitionFile\", \"value\": \"$definition_name\"},
                {\"name\": \"baseUrl\", \"value\": \"$base_url\"}
            ],
            \"tags\": [$tags]
        }"
}

add_cardigann_indexer "YTS" "yts" "https://yts.gg" ""
add_cardigann_indexer "1337x" "1337x" "https://1337x.to" "$FLARE_TAG_ID"
add_cardigann_indexer "EZTV" "eztv" "https://eztvx.to" ""

# --- Connect Radarr as app ---
api_post_json "Prowlarr connected to Radarr" \
    "$PROWLARR_URL/api/v1/applications" \
    "$PROWLARR_KEY" \
    "{
        \"name\": \"Radarr\",
        \"implementation\": \"Radarr\",
        \"configContract\": \"RadarrSettings\",
        \"syncLevel\": \"fullSync\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:$PROWLARR_PORT\"},
            {\"name\": \"baseUrl\", \"value\": \"http://radarr:$RADARR_PORT\"},
            {\"name\": \"apiKey\", \"value\": \"$RADARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]}
        ],
        \"tags\": []
    }"

# --- Connect Sonarr as app ---
api_post_json "Prowlarr connected to Sonarr" \
    "$PROWLARR_URL/api/v1/applications" \
    "$PROWLARR_KEY" \
    "{
        \"name\": \"Sonarr\",
        \"implementation\": \"Sonarr\",
        \"configContract\": \"SonarrSettings\",
        \"syncLevel\": \"fullSync\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:$PROWLARR_PORT\"},
            {\"name\": \"baseUrl\", \"value\": \"http://sonarr:$SONARR_PORT\"},
            {\"name\": \"apiKey\", \"value\": \"$SONARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080]}
        ],
        \"tags\": []
    }"

# --- Trigger Prowlarr to sync indexers to apps ---
api_post_json "Indexer sync triggered" \
    "$PROWLARR_URL/api/v1/command" \
    "$PROWLARR_KEY" \
    '{"name": "ApplicationIndexerSync"}'

echo ""

# ============================================================
# 6. Configure Seerr
# ============================================================

echo -e "${CYAN}[6/6] Configuring Seerr...${NC}"
echo ""
if [[ "$NON_INTERACTIVE" == true ]]; then
    warn "Non-interactive mode: skipping Seerr Emby sign-in prompt."
    warn "Manually open $SEERR_URL, select \"Use your Emby account\","
    warn "and enter http://emby:8096 as the Emby URL."
else
    echo -e "  ${YELLOW}ACTION NEEDED:${NC} Open ${CYAN}$SEERR_URL${NC} in your browser"
    echo "  1. Click \"Use your Emby account\""
    echo -e "  2. Enter Emby URL: ${CYAN}http://emby:8096${NC}"
    echo "  3. Enter your Emby username and password"
    echo ""
    read -p "  Press Enter after you've signed in to Seerr..."
    echo ""
    sleep 3
fi

# Get Seerr API key from settings
# (settings/main needs a login, so read the key from Seerr's settings file like the other apps)
SEERR_SETTINGS="$CONFIG_DIR/seerr/settings.json"
SEERR_KEY=""
if [[ -f "$SEERR_SETTINGS" ]]; then
    SEERR_KEY=$(grep -m1 -o '"apiKey": *"[^"]*"' "$SEERR_SETTINGS" 2>/dev/null | cut -d'"' -f4 || true)
fi

if [[ -z "$SEERR_KEY" ]]; then
    warn "Could not get Seerr API key. You may need to configure Radarr/Sonarr in Seerr manually."
    warn "Go to Seerr Settings > Services and add Radarr (${RADARR_URL#http://}) and Sonarr (${SONARR_URL#http://})."
else
    # Get default quality profile and root folder IDs from Radarr
    RADARR_PROFILE_ID=$(curl -fsS "$RADARR_URL/api/v3/qualityprofile" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    RADARR_PROFILE_ID="${RADARR_PROFILE_ID:-1}"
    RADARR_PROFILE_NAME=$(curl -fsS "$RADARR_URL/api/v3/qualityprofile" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -m1 -o '"name": *"[^"]*"' | cut -d'"' -f4 || true)
    RADARR_PROFILE_NAME="${RADARR_PROFILE_NAME:-Any}"

    RADARR_ROOT_ID=$(curl -fsS "$RADARR_URL/api/v3/rootfolder" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    RADARR_ROOT_ID="${RADARR_ROOT_ID:-1}"

    # Get default quality profile and root folder IDs from Sonarr
    SONARR_PROFILE_ID=$(curl -fsS "$SONARR_URL/api/v3/qualityprofile" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    SONARR_PROFILE_ID="${SONARR_PROFILE_ID:-1}"
    SONARR_PROFILE_NAME=$(curl -fsS "$SONARR_URL/api/v3/qualityprofile" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -m1 -o '"name": *"[^"]*"' | cut -d'"' -f4 || true)
    SONARR_PROFILE_NAME="${SONARR_PROFILE_NAME:-Any}"

    SONARR_ROOT_ID=$(curl -fsS "$SONARR_URL/api/v3/rootfolder" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    SONARR_ROOT_ID="${SONARR_ROOT_ID:-1}"

    # Add Radarr to Seerr
    api_post_json "Seerr connected to Radarr" \
        "$SEERR_URL/api/v1/settings/radarr" \
        "$SEERR_KEY" \
        "{
            \"name\": \"Radarr\",
            \"hostname\": \"radarr\",
            \"port\": $RADARR_PORT,
            \"apiKey\": \"$RADARR_KEY\",
            \"useSsl\": false,
            \"activeProfileId\": $RADARR_PROFILE_ID,
            \"activeProfileName\": \"$RADARR_PROFILE_NAME\",
            \"activeDirectory\": \"/data/movies\",
            \"minimumAvailability\": \"released\",
            \"is4k\": false,
            \"isDefault\": true,
            \"externalUrl\": \"$RADARR_URL\"
        }"

    # Add Sonarr to Seerr
    api_post_json "Seerr connected to Sonarr" \
        "$SEERR_URL/api/v1/settings/sonarr" \
        "$SEERR_KEY" \
        "{
            \"name\": \"Sonarr\",
            \"hostname\": \"sonarr\",
            \"port\": $SONARR_PORT,
            \"apiKey\": \"$SONARR_KEY\",
            \"useSsl\": false,
            \"activeProfileId\": $SONARR_PROFILE_ID,
            \"activeProfileName\": \"$SONARR_PROFILE_NAME\",
            \"activeDirectory\": \"/data/tvshows\",
            \"activeAnimeProfileId\": $SONARR_PROFILE_ID,
            \"activeAnimeProfileName\": \"$SONARR_PROFILE_NAME\",
            \"activeAnimeDirectory\": \"/data/tvshows\",
            \"is4k\": false,
            \"isDefault\": true,
            \"enableSeasonFolders\": true,
            \"externalUrl\": \"$SONARR_URL\"
        }"
fi

echo ""

# ============================================================
# Done!
# ============================================================

echo "=============================="
echo -e "  ${GREEN}Configuration complete!${NC}"
echo "=============================="
echo ""
echo "Your services are ready:"
echo ""
echo "  Seerr (browse & request):  $SEERR_URL"
echo "  Emby (watch):              $(topology_url emby)"
echo "  Flood (downloads):         $(topology_url flood)"
echo "  ruTorrent (alt UI):        $(topology_url rtorrent)"
echo ""
echo "  Radarr (movie admin):      $RADARR_URL"
echo "  Sonarr (TV admin):         $SONARR_URL"
echo "  Prowlarr (indexer admin):  $PROWLARR_URL"
echo "  Bazarr (subtitles):        $(topology_url bazarr)"
echo ""
echo "  Saved credentials:         $CREDS_FILE"
echo ""
echo "To request a movie or show, open Seerr and search for it."
echo "Everything else is automatic."
echo ""
