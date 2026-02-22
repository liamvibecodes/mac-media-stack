# Media Server Setup Guide

A personal media server that automatically finds, downloads, and organizes movies and TV shows. You browse a Netflix-like interface, click what you want, and it handles the rest.

**What you'll have when done:**
- Seerr: Netflix-style browsing and request UI (this is what you'll use day-to-day)
- Plex: Plays your media on any device (TV, phone, laptop)
- Everything else runs in the background automatically

**Time to complete:** About 20 minutes

---
## Quick Option: One-Command Install
If you already have OrbStack (or Docker Desktop) and Plex installed, you can run a single command that handles everything:
```bash
curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack/main/bootstrap.sh | bash
```
It will prompt you for VPN keys and walk you through the Seerr login. If you'd rather do each step yourself, continue with the manual guide below.
---
## What You Need
- A Mac (any recent macOS)
- [OrbStack](https://orbstack.dev) (recommended) or [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- An internet connection
- Your VPN keys (two values: a private key and an address)
- A free Plex account (create one at https://plex.tv if you don't have one)
---
## Step 1: Install A Container Runtime
You can use OrbStack (recommended) or Docker Desktop. Both run the same `docker` commands.

### Option A: OrbStack (Recommended)
1. Install OrbStack:
```bash
brew install --cask orbstack
```
2. Open OrbStack from Applications
3. Wait for it to fully start, then run:
```bash
docker info
```
If it prints Docker system information, you're ready.

### Option B: Docker Desktop
1. Go to https://www.docker.com/products/docker-desktop/
2. Click "Download for Mac"
   - If you have an M-series Mac (M1, M2, M3, M4): choose "Apple Silicon"
   - If you're not sure, click the Apple icon top-left of your screen > "About This Mac" and check the chip
3. Open the downloaded `.dmg` file
4. Drag Docker to your Applications folder
5. Open Docker Desktop from Applications
6. It will ask for your password to install components. Enter it.
7. Wait for it to finish starting (the whale icon in your menu bar will stop animating)
8. In Docker Desktop settings (gear icon), go to "General" and make sure "Start Docker Desktop when you sign in" is checked
---
## Step 2: Install Plex
Plex is the app that actually plays your media on your TV, phone, etc.
1. Go to https://www.plex.tv/media-server-downloads/
2. Under "Plex Media Server", choose macOS
3. Open the downloaded file and drag Plex to Applications
4. Open Plex Media Server from Applications
5. It will appear as an icon in your menu bar (an orange arrow)
6. In Plex's menu bar icon, click "Open Plex" to open the web interface
7. Sign in with your Plex account
8. Skip the initial library setup for now (we'll point it at the right folders later)
---
## Step 3: Download This Project
1. Open Terminal (search "Terminal" in Spotlight, or find it in Applications > Utilities)
2. Run these commands one at a time (copy and paste each line, then press Enter):
```bash
cd ~
git clone https://github.com/liamvibecodes/mac-media-stack.git
cd mac-media-stack
```
If you don't have git installed, your Mac will prompt you to install Command Line Tools. Click "Install" and wait, then run the commands again.
---
## Step 4: Run the Setup Script
This creates all the folders and prepares your configuration file.
```bash
bash scripts/setup.sh
```
You should see "Setup complete!" at the end.
---
## Step 5: Add Your VPN Keys
You need two values from your ProtonVPN account: a **WireGuard Private Key** and a **WireGuard Address**. See the ProtonVPN WireGuard setup page to generate them, or use the ones provided to you.
1. Open the `.env` file in TextEdit:
```bash
open -a TextEdit .env
```
2. Find these two lines near the bottom:
```
WIREGUARD_PRIVATE_KEY=your_wireguard_private_key_here
WIREGUARD_ADDRESSES=your_wireguard_address_here
```
3. Replace the placeholder text with your actual values. For example:
```
WIREGUARD_PRIVATE_KEY=aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890abcdefg=
WIREGUARD_ADDRESSES=10.2.0.2/32
```
4. Save and close TextEdit (Cmd+S, then Cmd+Q)
---
## Step 6: Start the Stack
```bash
docker compose up -d
```
This will download everything it needs (about 2-3 GB, may take a few minutes on the first run). You'll see each service being created.
When it's done, wait about 30 seconds for everything to start up, then run the health check:
```bash
bash scripts/health-check.sh
```
Everything should show OK. If VPN shows FAIL, double-check your WireGuard keys in Step 5.

Optional: enable automatic container updates (Watchtower):
```bash
docker compose --profile autoupdate up -d watchtower
```
---
## Step 7: Set Up Plex Libraries
1. Open Plex in your browser: http://localhost:32400/web
2. Go to Settings (wrench icon) > Libraries > Add Library
3. Add a **Movies** library:
   - Type: Movies
   - Add folder: click "Browse" and navigate to your home folder > Media > Movies
4. Add a **TV Shows** library:
   - Type: TV Shows
   - Add folder: click "Browse" and navigate to your home folder > Media > TV Shows
5. That's it. Plex will automatically scan these folders whenever new media appears.
**Important:** Always access Plex at `http://localhost:32400/web` from the server Mac itself. This avoids the "Plex Pass" paywall for remote streaming setup.
---
## Step 8: Auto-Configure Everything Else
This script automatically sets up all the connections between services. It configures the download client, indexers, and search providers so you don't have to touch any of that manually.
```bash
bash scripts/configure.sh
```
The script will:
- Configure the download client (qBittorrent) with the right settings
- Set up all the search indexers (where to find movies/shows)
- Connect everything together (Prowlarr, Radarr, Sonarr, Seerr)
- Ask you to sign in to Seerr with Plex (one browser click)

At the end it will print your qBittorrent password. Save it somewhere just in case, but you shouldn't need it for normal use.
## Step 9: Install Auto-Healer (Optional but Recommended)
This installs a background job that checks your stack every hour. If the VPN goes down or a container stops, it automatically restarts it. Set it and forget it.
```bash
bash scripts/install-auto-heal.sh
```
Logs go to `~/Media/logs/auto-heal.log` if you ever want to check what it's been doing.
To remove it later:
```bash
launchctl unload ~/Library/LaunchAgents/com.media-stack.auto-heal.plist
rm ~/Library/LaunchAgents/com.media-stack.auto-heal.plist
```
---
## You're Done!
**Day-to-day usage:**
- Open http://localhost:5055 (Seerr) to browse and request movies/shows
- Open http://localhost:32400/web (Plex) to watch your media
- Everything else is automatic

**Bookmarks to save:**

| What | URL |
|------|-----|
| Seerr (browse/request) | http://localhost:5055 |
| Plex (watch) | http://localhost:32400/web |

You probably won't need these, but just in case:

| What | URL |
|------|-----|
| Radarr (movies admin) | http://localhost:7878 |
| Sonarr (TV admin) | http://localhost:8989 |
| qBittorrent (downloads) | http://localhost:8080 |
**What happens automatically:**
- New requests in Seerr get searched and downloaded
- Downloads are automatically imported into Plex
- Subtitles are auto-fetched (English)
- If enabled, container updates happen at 4am daily (Watchtower)
- Everything survives reboots (Docker + Plex both auto-start)
---
## Troubleshooting
**Nothing is working after reboot:**
Open OrbStack or Docker Desktop. Wait 30 seconds. Run `bash scripts/health-check.sh`.
**VPN health check fails:**
Double-check your WireGuard keys in `.env`. Make sure there are no extra spaces. Then restart:
```bash
docker compose restart gluetun
```
**Downloads are stuck or slow:**
Open qBittorrent (http://localhost:8080) and check if torrents are active. If everything shows "stalled", the VPN tunnel may be down. Restart gluetun:
```bash
docker compose restart gluetun
```
**Plex doesn't see new movies:**
Plex scans periodically. To force a scan, open Plex, go to your library, and click the refresh icon. Or make sure the library folder paths are correct (Step 7).
**"Permission denied" errors:**
Make sure your PUID/PGID in `.env` match your Mac user. Run `id -u` in Terminal to check.
**Want to stop everything:**
```bash
cd ~/mac-media-stack
docker compose down
```
**Want to start everything again:**
```bash
cd ~/mac-media-stack
docker compose up -d
```
**Need help?**
Run the health check and share a screenshot with whoever set this up for you:
```bash
bash scripts/health-check.sh
```
