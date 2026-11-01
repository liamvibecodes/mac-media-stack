#!/bin/bash
# Media Stack Auto-Configurator
# Run this ONCE after "docker compose up -d" to configure all services
# (the "Connect the services" step in SETUP.md).
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

get_api_key() {
    local service="$1"
    local config_path="$CONFIG_DIR/$service/config.xml"
    local max_attempts=30
    local attempt=0
    local key

    while [[ $attempt -lt $max_attempts ]]; do
        if [[ -f "$config_path" ]]; then
            key=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$config_path" 2>/dev/null | sed 's/<[^>]*>//g')
            if [[ -n "$key" ]]; then
                echo "$key"
                return 0
            fi
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    ui_fail "Could not read API key for $service" >&2
    return 1
}

# GET an *arr/Prowlarr API endpoint.
arr_get() {
    curl -fsS "$1" -H "X-Api-Key: $2" 2>/dev/null
}

# First numeric "id" / first "name" string in the JSON read from stdin.
first_json_id() { grep -o '"id":[0-9]*' | head -1 | cut -d: -f2; }
first_json_name() { grep -m1 -o '"name": *"[^"]*"' | cut -d'"' -f4; }

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

# Registers an *arr app in Prowlarr so the indexers sync to it.
connect_prowlarr_app() {
    local name="$1"
    local host="$2"
    local port="$3"
    local api_key="$4"
    local categories="$5"

    api_post_json "Prowlarr connected to $name" \
        "$PROWLARR_URL/api/v1/applications" \
        "$PROWLARR_KEY" \
        "{
            \"name\": \"$name\",
            \"implementation\": \"$name\",
            \"configContract\": \"${name}Settings\",
            \"syncLevel\": \"fullSync\",
            \"fields\": [
                {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:$PROWLARR_PORT\"},
                {\"name\": \"baseUrl\", \"value\": \"http://$host:$port\"},
                {\"name\": \"apiKey\", \"value\": \"$api_key\"},
                {\"name\": \"syncCategories\", \"value\": [$categories]}
            ],
            \"tags\": []
        }"
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
ui_ok "Radarr API key: ${RADARR_KEY:0:8}..."

SONARR_KEY=$(get_api_key "sonarr")
ui_ok "Sonarr API key: ${SONARR_KEY:0:8}..."

PROWLARR_KEY=$(get_api_key "prowlarr")
ui_ok "Prowlarr API key: ${PROWLARR_KEY:0:8}..."

echo ""

# ============================================================
# 3. Configure rTorrent
# ============================================================

echo -e "${CYAN}[3/6] Configuring rTorrent...${NC}"
echo ""
ui_ok "rTorrent needs no setup (labels and paths come from Radarr/Sonarr)"

save_credentials || ui_info "Could not write $CREDS_FILE (API keys are under Settings > General in each app). Continuing."

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
    -d '{"label": "flaresolverr"}' | first_json_id)
FLARE_TAG_ID="${FLARE_TAG_ID:-1}"
ui_ok "FlareSolverr tag created (ID: $FLARE_TAG_ID)"

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
add_cardigann_indexer "YTS" "yts" "https://yts.gg" ""
add_cardigann_indexer "1337x" "1337x" "https://1337x.to" "$FLARE_TAG_ID"
add_cardigann_indexer "EZTV" "eztv" "https://eztvx.to" ""

# --- Connect Radarr and Sonarr as apps ---
connect_prowlarr_app Radarr radarr "$RADARR_PORT" "$RADARR_KEY" \
    "2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080"
connect_prowlarr_app Sonarr sonarr "$SONARR_PORT" "$SONARR_KEY" \
    "5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080"

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
    ui_info "Non-interactive mode: skipping Seerr Emby sign-in prompt."
    ui_info "Manually open $SEERR_URL, select \"Use your Emby account\","
    ui_info "and enter http://emby:8096 as the Emby URL."
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
    ui_info "Could not get Seerr API key. You may need to configure Radarr/Sonarr in Seerr manually."
    ui_info "Go to Seerr Settings > Services and add Radarr (${RADARR_URL#http://}) and Sonarr (${SONARR_URL#http://})."
else
    # Get default quality profile from Radarr
    RADARR_PROFILE_ID=$(arr_get "$RADARR_URL/api/v3/qualityprofile" "$RADARR_KEY" | first_json_id)
    RADARR_PROFILE_ID="${RADARR_PROFILE_ID:-1}"
    RADARR_PROFILE_NAME=$(arr_get "$RADARR_URL/api/v3/qualityprofile" "$RADARR_KEY" | first_json_name || true)
    RADARR_PROFILE_NAME="${RADARR_PROFILE_NAME:-Any}"

    # Get default quality profile from Sonarr
    SONARR_PROFILE_ID=$(arr_get "$SONARR_URL/api/v3/qualityprofile" "$SONARR_KEY" | first_json_id)
    SONARR_PROFILE_ID="${SONARR_PROFILE_ID:-1}"
    SONARR_PROFILE_NAME=$(arr_get "$SONARR_URL/api/v3/qualityprofile" "$SONARR_KEY" | first_json_name || true)
    SONARR_PROFILE_NAME="${SONARR_PROFILE_NAME:-Any}"

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
