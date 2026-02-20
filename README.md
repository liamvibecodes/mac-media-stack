<div align="center">
  <br>
  <a href="#one-command-install">
    <img src="https://img.shields.io/badge/MAC_MEDIA_STACK-00C853?style=for-the-badge&logo=apple&logoColor=white" alt="Mac Media Stack" height="40" />
  </a>
  <br><br>
  <strong>Self-hosted media server for macOS</strong>
  <br>
  <sub>Automatically find, download, and organize movies and TV shows.<br>Browse a Netflix-like interface, click what you want, and it handles the rest.</sub>
  <br><br>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white" />
  <img src="https://img.shields.io/badge/Plex-EBAF00?style=flat-square&logo=plex&logoColor=white" />
  <img src="https://img.shields.io/badge/Sonarr-00CCFF?style=flat-square&logo=sonarr&logoColor=white" />
  <img src="https://img.shields.io/badge/Radarr-FFC230?style=flat-square&logo=radarr&logoColor=black" />
  <img src="https://img.shields.io/badge/qBittorrent-2F67BA?style=flat-square&logo=qbittorrent&logoColor=white" />
  <img src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white" />
  <br><br>
  <img src="https://img.shields.io/github/stars/liamvibecodes/mac-media-stack?style=flat-square&color=yellow" />
  <img src="https://img.shields.io/github/license/liamvibecodes/mac-media-stack?style=flat-square" />
  <br><br>
</div>

## Why This One?

There are dozens of *arr stack Docker Compose repos on GitHub. Almost all of them dump a compose file and leave you to figure out the rest. This one is different:

- **One command to install.** Clone, configure, and start everything with a single `curl | bash`. No 45-minute manual setup.
- **Auto-configures itself.** The configure script wires up Radarr, Sonarr, Prowlarr, Seerr, and qBittorrent via their APIs. No clicking through 6 different web UIs.
- **Built for macOS.** Native paths, launchd instead of systemd, Docker Desktop instead of bare Docker. Not a Linux guide with "should work on Mac" in the footnotes.
- **Self-healing.** Hourly health checks restart anything that goes down. VPN drops, container crashes, stalled downloads — handled automatically.

---

## What's Included

| Service | What It Does |
|---------|-------------|
| **Seerr** | Netflix-style UI for browsing and requesting movies/shows |
| **Plex** | Plays your media on any device (TV, phone, laptop) |
| **Radarr** | Automatically finds and downloads movies |
| **Sonarr** | Automatically finds and downloads TV shows |
| **Prowlarr** | Manages search indexers for Radarr/Sonarr |
| **qBittorrent** | Downloads torrents through a VPN tunnel |
| **Gluetun** | VPN container (ProtonVPN WireGuard) so downloads are private |
| **Bazarr** | Auto-fetches subtitles |
| **FlareSolverr** | Bypasses Cloudflare protection on certain indexers |
| **Watchtower** | Optional auto-updater (opt-in profile) |

## Requirements

- macOS (any recent version)
- Docker Desktop
- A Plex account (free)
- ProtonVPN WireGuard credentials

## One-Command Install

Requires Docker Desktop and Plex already installed. Handles everything else.

```bash
curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack/main/bootstrap.sh | bash
```

<details>
<summary>See it in action</summary>
<br>
<img src="demo.gif" alt="Mac Media Stack install demo" width="700" />
</details>

## Manual Quick Start

If you prefer to run each step yourself:

```bash
git clone https://github.com/liamvibecodes/mac-media-stack.git
cd mac-media-stack
bash scripts/setup.sh        # creates folders, generates .env
# edit .env and add your VPN keys
docker compose up -d          # start everything
docker compose --profile autoupdate up -d watchtower  # optional auto-updates
bash scripts/configure.sh     # auto-configure all services
```

## Full Setup Guide

See [SETUP.md](SETUP.md) for the complete step-by-step walkthrough.
Pinned digest matrix: [IMAGE_LOCK.md](IMAGE_LOCK.md)

By default, Seerr is bound to `127.0.0.1` for safer local-only access. Set `SEERR_BIND_IP=0.0.0.0` in `.env` only if you intentionally want LAN exposure.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup.sh` | Creates folder structure and .env file |
| `scripts/configure.sh` | Auto-configures all service connections |
| `scripts/health-check.sh` | Checks if everything is running correctly |
| `scripts/auto-heal.sh` | Hourly self-healer (restarts VPN/containers if down) |
| `scripts/install-auto-heal.sh` | Installs auto-heal as a background job via launchd |
| `scripts/refresh-image-lock.sh` | Refreshes pinned image digests and regenerates IMAGE_LOCK.md |

## What It Looks Like

<img src="ui-flow.gif" alt="Request to streaming UI flow" width="700" />

## Day-to-Day Usage

| What | Where |
|------|-------|
| Browse and request movies/shows | http://localhost:5055 |
| Watch your media | http://localhost:32400/web |

Everything else is automatic. Requests get searched, downloaded, imported, and subtitled without any manual steps.

## How It Works

<img src="flow.gif" alt="Request to streaming flow" width="700" />

```
You (Seerr) -> Radarr/Sonarr -> Prowlarr (search) -> qBittorrent (download via VPN) -> Plex (watch)
                                                        Bazarr (subtitles) ^
```

All services run as Docker containers. Plex runs natively on macOS. Download traffic routes through ProtonVPN. Everything else uses your normal internet connection.

## Looking for More?

Check out [mac-media-stack-advanced](https://github.com/liamvibecodes/mac-media-stack-advanced) for the full power-user setup with transcoding (Tdarr), TRaSH quality profiles (Recyclarr), Plex metadata automation (Kometa), download watchdog, VPN failover, automated backups, and optional music management (Lidarr + Tidarr for Hi-Res FLAC from Tidal).

## Author

Built by [@liamvibecodes](https://github.com/liamvibecodes)

## License

[MIT](LICENSE)
