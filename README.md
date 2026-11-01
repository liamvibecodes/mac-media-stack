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
  <img src="https://img.shields.io/badge/OrbStack-000000?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSIxMCIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&logoColor=white" />
  <img src="https://img.shields.io/badge/Emby-52B54B?style=flat-square&logo=emby&logoColor=white" />
  <img src="https://img.shields.io/badge/Sonarr-00CCFF?style=flat-square&logo=sonarr&logoColor=white" />
  <img src="https://img.shields.io/badge/Radarr-FFC230?style=flat-square&logo=radarr&logoColor=black" />
  <img src="https://img.shields.io/badge/rTorrent-2F67BA?style=flat-square" />
  <img src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white" />
  <br><br>
  <img src="https://img.shields.io/github/stars/alexgrpopa/mac-media-stack?style=flat-square&color=yellow" />
  <img src="https://img.shields.io/github/license/alexgrpopa/mac-media-stack?style=flat-square" />
  <br><br>
</div>

## Why This One?

There are dozens of *arr stack Docker Compose repos on GitHub. Almost all of them dump a compose file and leave you to figure out the rest. This one is different:

- **One command to install.** Clone, configure, and start everything with a single `curl | bash`. No 45-minute manual setup.
- **Auto-configures itself.** The configure script wires up Radarr, Sonarr, Prowlarr, and Seerr via their APIs. No clicking through 6 different web UIs.
- **Built for macOS.** Native paths, launchd instead of systemd, OrbStack or Docker Desktop instead of bare Docker. Not a Linux guide with "should work on Mac" in the footnotes.
- **Self-healing.** Hourly health checks restart anything that goes down. VPN drops, container crashes, stalled downloads — handled automatically.

---

## What's Included

| Service | What It Does |
|---------|-------------|
| **Seerr** | Netflix-style UI for browsing and requesting movies/shows |
| **Emby** | Plays your media on any device (TV, phone, laptop) |
| **Caddy** | Optional friendly hostnames for every UI, like `seerr.media.lan` (opt-in via `--proxy` flag) |
| **Radarr** | Automatically finds and downloads movies |
| **Sonarr** | Automatically finds and downloads TV shows |
| **Prowlarr** | Manages search indexers for Radarr/Sonarr |
| **rTorrent + Flood** | Downloads torrents through a VPN tunnel (Flood is the web UI) |
| **Gluetun** | VPN container (ProtonVPN or Mullvad, WireGuard) so downloads are private |
| **Bazarr** | Auto-fetches subtitles |
| **FlareSolverr** | Bypasses Cloudflare protection on certain indexers |
| **Watchtower** | Optional auto-updater (opt-in profile) |

## Requirements

- macOS (any recent version)
- [OrbStack](https://orbstack.dev) (recommended) or [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- An Emby account (a local account is enough)
- ProtonVPN or Mullvad WireGuard credentials (Mullvad has no port forwarding, so seeding is slower)

> **Why OrbStack?** It starts in ~2 seconds (vs 30s for Docker Desktop), uses ~1GB RAM (vs 4GB), and has 2-10x faster file I/O. It's a drop-in replacement that runs the same Docker commands. Docker Desktop works fine too.

## One-Command Install

Requires OrbStack (or Docker Desktop). Handles everything else.

```bash
curl -fsSL https://raw.githubusercontent.com/alexgrpopa/mac-media-stack/main/bootstrap.sh | bash
```

Optional flags when running from a local clone:

```bash
bash bootstrap.sh --media-dir /Volumes/T9/Media --install-dir ~/mac-media-stack --non-interactive
bash bootstrap.sh --mullvad   # use Mullvad instead of ProtonVPN
bash bootstrap.sh --proxy     # friendly hostnames like seerr.media.lan
```

## Update Existing Clone

Already cloned an older version and want the latest release tag without reinstalling?

One-liner (run inside your existing clone directory):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/alexgrpopa/mac-media-stack/main/scripts/update-to-latest-release.sh)
```

Local script (once present):

```bash
bash scripts/update-to-latest-release.sh
```

<details>
<summary>See it in action</summary>
<br>
<img src="demo.gif" alt="Mac Media Stack install demo" width="700" />
</details>

### Media Server and Torrent Client

**Emby** is the media server and runs in Docker. The core server is free; Emby Premiere is optional and unlocks extras like hardware transcoding.

**rTorrent + Flood** is the torrent client. It runs behind the VPN, and Flood (the web UI) is at http://localhost:3000. ruTorrent is also available at http://localhost:8080. See [SETUP.md](SETUP.md#about-the-torrent-client) for details.

## Manual Quick Start

If you prefer to run each step yourself:

```bash
git clone https://github.com/alexgrpopa/mac-media-stack.git
cd mac-media-stack
bash scripts/setup.sh        # creates folders, generates .env
# edit .env and add your VPN keys
bash scripts/doctor.sh       # preflight validation before first boot
docker compose up -d         # start everything
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
| `scripts/doctor.sh` | Runs preflight checks (runtime, env, compose, ports) |
| `scripts/configure.sh` | Auto-configures all service connections |
| `scripts/health-check.sh` | Checks if everything is running correctly |
| `scripts/auto-heal.sh` | Hourly self-healer (restarts VPN/containers if down) |
| `scripts/install-auto-heal.sh` | Installs auto-heal as a background job via launchd |
| `scripts/update-to-latest-release.sh` | Updates an older clone to the latest tagged release safely |
| `scripts/refresh-image-lock.sh` | Refreshes pinned image digests and regenerates IMAGE_LOCK.md |

## What It Looks Like

<img src="ui-flow.gif" alt="Request to streaming UI flow" width="700" />

## Day-to-Day Usage

| What | Where |
|------|-------|
| Browse and request movies/shows | http://localhost:5055 |
| Watch your media (Emby) | http://localhost:8096 |
| Manage downloads (Flood) | http://localhost:3000 |

Everything else is automatic. Requests get searched, downloaded, imported, and subtitled without any manual steps.

## How It Works

<img src="flow.gif" alt="Request to streaming flow" width="700" />

```
You (Seerr) -> Radarr/Sonarr -> Prowlarr (search) -> rTorrent (download via VPN) -> Emby (watch)
                                                        Bazarr (subtitles) ^
```

All services run as Docker containers. Download traffic routes through your VPN (ProtonVPN or Mullvad). Everything else uses your normal internet connection.

## Looking for More?

Check out [mac-media-stack-advanced](https://github.com/liamvibecodes/mac-media-stack-advanced) for the full power-user setup with transcoding (Tdarr), TRaSH quality profiles (Recyclarr), Plex metadata automation (Kometa), download watchdog, VPN failover, automated backups, and optional music management (Lidarr + Tidarr for Hi-Res FLAC from Tidal).
Already running basic and want to migrate? Follow the upgrade guide: [mac-media-stack-advanced/UPGRADE.md](https://github.com/liamvibecodes/mac-media-stack-advanced/blob/main/UPGRADE.md).

## Companion Tools

| Tool | What It Does |
|------|-------------|
| [mac-media-stack-permissions](https://github.com/liamvibecodes/mac-media-stack-permissions) | Audit and fix file permissions across your stack |
| [mac-media-stack-backup](https://github.com/liamvibecodes/mac-media-stack-backup) | Automated backup and restore for configs and databases |

## Author

Built by [@liamvibecodes](https://github.com/liamvibecodes)

## License

[MIT](LICENSE)
