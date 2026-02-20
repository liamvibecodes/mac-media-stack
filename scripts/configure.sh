#!/bin/bash
# Media Stack Auto-Configurator
# Run this ONCE after "docker compose up -d" to configure all services.
# Replaces manual Steps 8-10 from SETUP.md.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Load .env
if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${RED}Error:${NC} .env file not found. Run setup.sh first."
    exit 1
fi
source "$SCRIPT_DIR/.env"

# Permanent qBittorrent password (generated randomly)
QB_PASSWORD="media$(date +%s | shasum | head -c 8)"

# ============================================================
# Helper functions
# ============================================================

log() { echo -e "  ${GREEN}OK${NC}  $1"; }
warn() { echo -e "  ${YELLOW}..${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; }

wait_for_service() {
    local name="$1"
    local url="$2"
    local max_attempts="${3:-30}"
    local attempt=0

    warn "Waiting for $name..."
    while [[ $attempt -lt $max_attempts ]]; do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true)
        if [[ "$status" =~ ^(200|301|302|401|403)$ ]]; then
            log "$name is ready"
            return 0
        fi
        sleep 2
        ((attempt++))
    done
    fail "$name didn't start after $((max_attempts * 2)) seconds"
    return 1
}

get_api_key() {
    local service="$1"
    local config_path="$MEDIA_DIR/config/$service/config.xml"
    local max_attempts=15
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

wait_for_service "qBittorrent" "http://localhost:8080"
wait_for_service "Prowlarr" "http://localhost:9696"
wait_for_service "Radarr" "http://localhost:7878"
wait_for_service "Sonarr" "http://localhost:8989"
wait_for_service "Bazarr" "http://localhost:6767"
wait_for_service "FlareSolverr" "http://localhost:8191"
wait_for_service "Seerr" "http://localhost:5055"

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
# 3. Configure qBittorrent
# ============================================================

echo -e "${CYAN}[3/6] Configuring qBittorrent...${NC}"
echo ""

# Get temporary password from logs
QB_TEMP_PASS=$(docker logs qbittorrent 2>&1 | grep -o 'temporary password is provided for this session: [^ ]*' | tail -1 | awk '{print $NF}')

if [[ -z "$QB_TEMP_PASS" ]]; then
    # Try the older log format
    QB_TEMP_PASS=$(docker logs qbittorrent 2>&1 | grep -oP 'password: \K\S+' | tail -1)
fi

if [[ -z "$QB_TEMP_PASS" ]]; then
    warn "Could not find temp password. qBit may already be configured."
    # Try default admin/adminadmin
    QB_TEMP_PASS="adminadmin"
fi

# Authenticate with qBittorrent
QB_COOKIE=$(curl -s -c - "http://localhost:8080/api/v2/auth/login" \
    --data-urlencode "username=admin" \
    --data-urlencode "password=$QB_TEMP_PASS" 2>/dev/null | grep SID | awk '{print $NF}')

if [[ -z "$QB_COOKIE" ]]; then
    fail "Could not authenticate with qBittorrent"
    echo "  You may need to configure it manually at http://localhost:8080"
else
    # Set permanent password + all preferences in one call
    curl -s -b "SID=$QB_COOKIE" "http://localhost:8080/api/v2/app/setPreferences" \
        --data-urlencode "json={
            \"web_ui_password\": \"$QB_PASSWORD\",
            \"max_ratio\": 0,
            \"max_seeding_time\": 0,
            \"max_ratio_act\": 0,
            \"up_limit\": 1024,
            \"save_path\": \"/downloads/complete\",
            \"temp_path_enabled\": true,
            \"temp_path\": \"/downloads/incomplete\",
            \"preallocate_all\": false,
            \"add_trackers_enabled\": false
        }" >/dev/null 2>&1
    log "Password set and preferences configured"

    # Create download categories
    curl -s -b "SID=$QB_COOKIE" "http://localhost:8080/api/v2/torrents/createCategory" \
        --data-urlencode "category=radarr" \
        --data-urlencode "savePath=/downloads/complete/radarr" >/dev/null 2>&1
    curl -s -b "SID=$QB_COOKIE" "http://localhost:8080/api/v2/torrents/createCategory" \
        --data-urlencode "category=tv-sonarr" \
        --data-urlencode "savePath=/downloads/complete/tv-sonarr" >/dev/null 2>&1
    log "Download categories created (radarr, tv-sonarr)"
fi

echo ""

# ============================================================
# 4. Configure Radarr & Sonarr
# ============================================================

echo -e "${CYAN}[4/6] Configuring Radarr & Sonarr...${NC}"
echo ""

# --- Radarr: Add root folder ---
curl -s -o /dev/null "http://localhost:7878/api/v3/rootfolder" \
    -H "X-Api-Key: $RADARR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"path": "/movies", "accessible": true}' 2>/dev/null
log "Radarr root folder set to /movies"

# --- Radarr: Add qBittorrent download client ---
curl -s -o /dev/null "http://localhost:7878/api/v3/downloadclient" \
    -H "X-Api-Key: $RADARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"enable\": true,
        \"protocol\": \"torrent\",
        \"name\": \"qBittorrent\",
        \"implementation\": \"QBittorrent\",
        \"configContract\": \"QBittorrentSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"gluetun\"},
            {\"name\": \"port\", \"value\": 8080},
            {\"name\": \"username\", \"value\": \"admin\"},
            {\"name\": \"password\", \"value\": \"$QB_PASSWORD\"},
            {\"name\": \"movieCategory\", \"value\": \"radarr\"},
            {\"name\": \"recentMoviePriority\", \"value\": 0},
            {\"name\": \"olderMoviePriority\", \"value\": 0},
            {\"name\": \"initialState\", \"value\": 0},
            {\"name\": \"sequentialOrder\", \"value\": false},
            {\"name\": \"firstAndLast\", \"value\": false}
        ],
        \"removeCompletedDownloads\": true,
        \"removeFailedDownloads\": true
    }" 2>/dev/null
log "Radarr download client configured"

# --- Sonarr: Add root folder ---
curl -s -o /dev/null "http://localhost:8989/api/v3/rootfolder" \
    -H "X-Api-Key: $SONARR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"path": "/tv", "accessible": true}' 2>/dev/null
log "Sonarr root folder set to /tv"

# --- Sonarr: Add qBittorrent download client ---
curl -s -o /dev/null "http://localhost:8989/api/v3/downloadclient" \
    -H "X-Api-Key: $SONARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"enable\": true,
        \"protocol\": \"torrent\",
        \"name\": \"qBittorrent\",
        \"implementation\": \"QBittorrent\",
        \"configContract\": \"QBittorrentSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"gluetun\"},
            {\"name\": \"port\", \"value\": 8080},
            {\"name\": \"username\", \"value\": \"admin\"},
            {\"name\": \"password\", \"value\": \"$QB_PASSWORD\"},
            {\"name\": \"tvCategory\", \"value\": \"tv-sonarr\"},
            {\"name\": \"recentTvPriority\", \"value\": 0},
            {\"name\": \"olderTvPriority\", \"value\": 0},
            {\"name\": \"initialState\", \"value\": 0},
            {\"name\": \"sequentialOrder\", \"value\": false},
            {\"name\": \"firstAndLast\", \"value\": false}
        ],
        \"removeCompletedDownloads\": true,
        \"removeFailedDownloads\": true
    }" 2>/dev/null
log "Sonarr download client configured"

echo ""

# ============================================================
# 5. Configure Prowlarr
# ============================================================

echo -e "${CYAN}[5/6] Configuring Prowlarr...${NC}"
echo ""

# --- Create FlareSolverr tag (ID will be 1) ---
FLARE_TAG_ID=$(curl -s "http://localhost:9696/api/v1/tag" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"label": "flaresolverr"}' 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
FLARE_TAG_ID="${FLARE_TAG_ID:-1}"
log "FlareSolverr tag created (ID: $FLARE_TAG_ID)"

# --- Add FlareSolverr indexer proxy ---
curl -s -o /dev/null "http://localhost:9696/api/v1/indexerProxy" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"FlareSolverr\",
        \"implementation\": \"FlareSolverr\",
        \"configContract\": \"FlareSolverrSettings\",
        \"fields\": [
            {\"name\": \"host\", \"value\": \"http://flaresolverr:8191\"},
            {\"name\": \"requestTimeout\", \"value\": 60}
        ],
        \"tags\": [$FLARE_TAG_ID]
    }" 2>/dev/null
log "FlareSolverr proxy added"

# --- Add indexers ---

# Helper to add a Prowlarr indexer
add_indexer() {
    local name="$1"
    local implementation="$2"
    local base_url="$3"
    local tags="$4"

    curl -s -o /dev/null "http://localhost:9696/api/v1/indexer" \
        -H "X-Api-Key: $PROWLARR_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$name\",
            \"implementation\": \"$implementation\",
            \"configContract\": \"${implementation}Settings\",
            \"protocol\": \"torrent\",
            \"enable\": true,
            \"appProfileId\": 1,
            \"fields\": [
                {\"name\": \"baseUrl\", \"value\": \"$base_url\"},
                {\"name\": \"sortRequestLimit\", \"value\": 100},
                {\"name\": \"multiLanguages\", \"value\": []}
            ],
            \"tags\": [$tags]
        }" 2>/dev/null
    log "Indexer added: $name"
}

# Cardigann-based indexers use a different format
add_cardigann_indexer() {
    local name="$1"
    local definition_name="$2"
    local base_url="$3"
    local tags="$4"

    curl -s -o /dev/null "http://localhost:9696/api/v1/indexer" \
        -H "X-Api-Key: $PROWLARR_KEY" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"$name\",
            \"definitionName\": \"$definition_name\",
            \"implementation\": \"Cardigann\",
            \"configContract\": \"CardigannSettings\",
            \"protocol\": \"torrent\",
            \"enable\": true,
            \"appProfileId\": 1,
            \"fields\": [
                {\"name\": \"baseUrl\", \"value\": \"$base_url\"},
                {\"name\": \"sortRequestLimit\", \"value\": 100},
                {\"name\": \"multiLanguages\", \"value\": []}
            ],
            \"tags\": [$tags]
        }" 2>/dev/null
    log "Indexer added: $name"
}

add_cardigann_indexer "YTS" "yts" "https://yts.mx" ""
add_cardigann_indexer "1337x" "1337x" "https://1337x.to" "$FLARE_TAG_ID"
add_cardigann_indexer "EZTV" "eztv" "https://eztvx.to" ""
add_cardigann_indexer "TorrentGalaxy" "torrentgalaxy" "https://torrentgalaxy.to" ""

# --- Connect Radarr as app ---
curl -s -o /dev/null "http://localhost:9696/api/v1/applications" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Radarr\",
        \"implementation\": \"Radarr\",
        \"configContract\": \"RadarrSettings\",
        \"syncLevel\": \"fullSync\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
            {\"name\": \"baseUrl\", \"value\": \"http://radarr:7878\"},
            {\"name\": \"apiKey\", \"value\": \"$RADARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080]}
        ],
        \"tags\": []
    }" 2>/dev/null
log "Prowlarr connected to Radarr"

# --- Connect Sonarr as app ---
curl -s -o /dev/null "http://localhost:9696/api/v1/applications" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d "{
        \"name\": \"Sonarr\",
        \"implementation\": \"Sonarr\",
        \"configContract\": \"SonarrSettings\",
        \"syncLevel\": \"fullSync\",
        \"fields\": [
            {\"name\": \"prowlarrUrl\", \"value\": \"http://prowlarr:9696\"},
            {\"name\": \"baseUrl\", \"value\": \"http://sonarr:8989\"},
            {\"name\": \"apiKey\", \"value\": \"$SONARR_KEY\"},
            {\"name\": \"syncCategories\", \"value\": [5000, 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080]}
        ],
        \"tags\": []
    }" 2>/dev/null
log "Prowlarr connected to Sonarr"

# --- Trigger Prowlarr to sync indexers to apps ---
curl -s -o /dev/null "http://localhost:9696/api/v1/command" \
    -H "X-Api-Key: $PROWLARR_KEY" \
    -H "Content-Type: application/json" \
    -d '{"name": "SyncIndexers"}' 2>/dev/null
log "Indexer sync triggered"

echo ""

# ============================================================
# 6. Configure Seerr
# ============================================================

echo -e "${CYAN}[6/6] Configuring Seerr...${NC}"
echo ""
echo -e "  ${YELLOW}ACTION NEEDED:${NC} Open ${CYAN}http://localhost:5055${NC} in your browser"
echo "  and click \"Sign In With Plex\". Log in with your Plex account."
echo ""
read -p "  Press Enter after you've signed in to Seerr..."
echo ""

# Wait a moment for Seerr to process the login
sleep 3

# Get Seerr API key from settings
SEERR_KEY=$(curl -s "http://localhost:5055/api/v1/settings/main" 2>/dev/null | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)

if [[ -z "$SEERR_KEY" ]]; then
    warn "Could not get Seerr API key. You may need to configure Radarr/Sonarr in Seerr manually."
    warn "Go to Seerr Settings > Services and add Radarr (localhost:7878) and Sonarr (localhost:8989)."
else
    # Get default quality profile and root folder IDs from Radarr
    RADARR_PROFILE_ID=$(curl -s "http://localhost:7878/api/v3/qualityprofile" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    RADARR_PROFILE_ID="${RADARR_PROFILE_ID:-1}"

    RADARR_ROOT_ID=$(curl -s "http://localhost:7878/api/v3/rootfolder" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    RADARR_ROOT_ID="${RADARR_ROOT_ID:-1}"

    # Get default quality profile and root folder IDs from Sonarr
    SONARR_PROFILE_ID=$(curl -s "http://localhost:8989/api/v3/qualityprofile" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    SONARR_PROFILE_ID="${SONARR_PROFILE_ID:-1}"

    SONARR_ROOT_ID=$(curl -s "http://localhost:8989/api/v3/rootfolder" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    SONARR_ROOT_ID="${SONARR_ROOT_ID:-1}"

    # Add Radarr to Seerr
    curl -s -o /dev/null "http://localhost:5055/api/v1/settings/radarr" \
        -H "X-Api-Key: $SEERR_KEY" \
        -H "Content-Type: application/json" \
        -d "[{
            \"name\": \"Radarr\",
            \"hostname\": \"radarr\",
            \"port\": 7878,
            \"apiKey\": \"$RADARR_KEY\",
            \"useSsl\": false,
            \"activeProfileId\": $RADARR_PROFILE_ID,
            \"activeDirectory\": \"/movies\",
            \"is4k\": false,
            \"isDefault\": true,
            \"externalUrl\": \"http://localhost:7878\"
        }]" 2>/dev/null
    log "Seerr connected to Radarr"

    # Add Sonarr to Seerr
    curl -s -o /dev/null "http://localhost:5055/api/v1/settings/sonarr" \
        -H "X-Api-Key: $SEERR_KEY" \
        -H "Content-Type: application/json" \
        -d "[{
            \"name\": \"Sonarr\",
            \"hostname\": \"sonarr\",
            \"port\": 8989,
            \"apiKey\": \"$SONARR_KEY\",
            \"useSsl\": false,
            \"activeProfileId\": $SONARR_PROFILE_ID,
            \"activeDirectory\": \"/tv\",
            \"activeAnimeProfileId\": $SONARR_PROFILE_ID,
            \"activeAnimeDirectory\": \"/tv\",
            \"is4k\": false,
            \"isDefault\": true,
            \"enableSeasonFolders\": true,
            \"externalUrl\": \"http://localhost:8989\"
        }]" 2>/dev/null
    log "Seerr connected to Sonarr"
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
echo "  Seerr (browse & request):  http://localhost:5055"
echo "  Plex (watch):              http://localhost:32400/web"
echo "  qBittorrent (downloads):   http://localhost:8080"
echo "    Username: admin"
echo "    Password: $QB_PASSWORD"
echo ""
echo "  Radarr (movie admin):      http://localhost:7878"
echo "  Sonarr (TV admin):         http://localhost:8989"
echo "  Prowlarr (indexer admin):  http://localhost:9696"
echo "  Bazarr (subtitles):        http://localhost:6767"
echo ""
echo -e "  ${YELLOW}Save your qBittorrent password:${NC} $QB_PASSWORD"
echo ""
echo "To request a movie or show, open Seerr and search for it."
echo "Everything else is automatic."
echo ""
