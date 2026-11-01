# Media Stack Setup Guide

This guide shows how to install and use the media stack on a Mac. It takes about 20 minutes.

---

## 1. Introduction

### What the stack does

The stack finds, downloads, and sorts movies and TV shows for you. You request a title in a web page. The stack does the rest.

### Parts you use

| Part | Function | Address |
|------|----------|---------|
| Seerr | Browse and request titles | http://localhost:5055 |
| Emby | Play your media on a TV, phone, or computer | http://localhost:8096 |

### Parts that work in the background

| Part | Function | Address |
|------|----------|---------|
| Radarr | Manages movies | http://localhost:7878 |
| Sonarr | Manages TV shows | http://localhost:8989 |
| Prowlarr | Manages the search indexers | http://localhost:9696 |
| Bazarr | Gets subtitles | http://localhost:6767 |
| Flood | Web page for the torrent client | http://localhost:3000 |
| ruTorrent | Second web page for the torrent client | http://localhost:8080 |
| Gluetun | Sends all download traffic through the VPN | None |

All parts run in Docker containers. You do not install them one by one.

### What you need

- A Mac with a recent version of macOS.
- An internet connection.
- 50 GB of free disk space. Your media library needs more.
- A WireGuard private key and a WireGuard address from your VPN provider. The stack supports ProtonVPN and Mullvad.
- An Emby account. A local account is sufficient.

### About Emby

Emby is the media server. It runs in Docker, so you do not install it on macOS. The free version is sufficient. Emby Premiere is optional and adds features such as hardware transcoding.

### About the VPN

The stack sends all download traffic through a VPN. Compare the two providers:

| | ProtonVPN (default) | Mullvad |
|---|---|---|
| Port forwarding | Yes. Seeding is faster. | No. Seeding is slower. |
| Where to get the key | account.protonvpn.com/downloads#wireguard-configuration | mullvad.net/account, then WireGuard configuration |
| Setting in `.env` | `VPN_PROVIDER=protonvpn` | `VPN_PROVIDER=mullvad` |

Private trackers need good seeding. Use ProtonVPN for these trackers.

---

## 2. Quick install

Use the quick install if OrbStack or Docker Desktop is on your Mac. One command does all the steps in sections 3 to 5, except the optional ones.

```bash
curl -fsSL https://raw.githubusercontent.com/alexgrpopa/mac-media-stack/main/bootstrap.sh | bash
```

The command asks for your VPN keys. It also asks you to sign in to Seerr.

To change the install, add options:

| Option | Function |
|--------|----------|
| `--media-dir DIR` | Put the media in `DIR`. The default is `~/Media`. |
| `--install-dir DIR` | Put the project in `DIR`. The default is `~/mac-media-stack`. |
| `--mullvad` | Use Mullvad instead of ProtonVPN. |
| `--proxy` | Turn on friendly hostnames. Refer to [Friendly hostnames](#friendly-hostnames-optional). |
| `--non-interactive` | Do not ask questions. You must connect Seerr yourself. |

Example:

```bash
bash bootstrap.sh --media-dir /Volumes/T9/Media --install-dir ~/mac-media-stack
```

To do each step yourself, continue with section 3.

---

## 3. Install the tools and clone the project

### Install a container runtime

A container runtime runs the Docker containers. Install one of these:

**OrbStack (recommended).** It starts fast and uses little memory.

```bash
brew install --cask orbstack
```

You can also download OrbStack from https://orbstack.dev. Open OrbStack one time after the install.

**Docker Desktop.**

1. Go to https://www.docker.com/products/docker-desktop/.
2. Download the version for your Mac. Choose "Apple Silicon" for an M-series chip.
3. Open the `.dmg` file.
4. Move Docker to the Applications folder.
5. Open Docker Desktop.
6. Enter your password when the app asks for it.
7. Wait until the whale icon in the menu bar stops moving.
8. Open the settings. In "General", select "Start Docker Desktop when you sign in".

Both runtimes use the same `docker` and `docker compose` commands.

### Clone the project

1. Open Terminal. Search for "Terminal" in Spotlight.
2. Run these commands, one at a time:

```bash
cd ~
git clone https://github.com/alexgrpopa/mac-media-stack.git
cd mac-media-stack
```

If git is not installed, macOS asks you to install the Command Line Tools. Select "Install". Then run the commands again.

---

## 4. Configure

### Create the folders and the `.env` file

Run the setup script:

```bash
bash scripts/setup.sh
```

The script does these tasks:

- It creates the media folders: `downloads`, `movies`, `tvshows`, and `logs`.
- It creates a folder for the app settings.
- It creates the `.env` file.

The message "Setup complete!" shows when the script ends.

### Choose the folder locations

The default locations are:

- Media: `~/Media`
- App settings and databases: `~/Media/config`

To use other locations, add options to the script:

```bash
bash scripts/setup.sh --media-dir /Volumes/T9/Media --config-dir ~/mac-media-stack-config
```

> **CAUTION**
> Keep the app settings on a local disk. If the media is on a network share, do not put the settings on the share. The databases can lock or become damaged on network storage.

### Add the VPN keys

1. Get a WireGuard configuration file from your VPN provider.
   - ProtonVPN: Turn on **NAT-PMP (Port Forwarding)** when you create the file.
   - Mullvad: Select the **Linux** platform. Generate a key. Download the file.
2. Open the `.env` file:

```bash
open -a TextEdit .env
```

3. Find the line `WIREGUARD_PRIVATE_KEY=`. Paste the value of `PrivateKey` from the file.
4. Find the line `WIREGUARD_ADDRESSES=`. Paste the value of `Address` from the file.
5. Use only the IPv4 part of the address. An example is `10.2.0.2/32`. Do not use the part that starts with `fc00:`.
6. Make sure that no spaces are around the values.
7. Save the file.

For Mullvad, also set these lines in `.env`:

```
VPN_PROVIDER=mullvad
VPN_PORT_FORWARDING=off
VPN_COUNTRIES=Denmark
```

The option `--mullvad` of `bootstrap.sh` sets these lines for you.

### Check the other settings

The default values are correct for most Macs. Check these values in `.env`:

| Setting | Meaning | Default |
|---------|---------|---------|
| `PUID` and `PGID` | Your Mac user ID and group ID. Run `id -u` and `id -g` to see them. | `501` and `20` |
| `TIMEZONE` | Your time zone | `America/New_York` |
| `SEERR_BIND_IP` | Who can open Seerr. Use `127.0.0.1` for this Mac only. | `127.0.0.1` |

> **WARNING**
> If you set `SEERR_BIND_IP=0.0.0.0`, all devices on your network can open Seerr.

---

## 5. Start and set up

### Start the stack

1. Run the preflight checks:

```bash
bash scripts/doctor.sh
```

2. If a check fails, correct the problem. Then run the script again.
3. Start the containers:

```bash
docker compose up -d
```

The first start downloads about 2 to 3 GB. This can take several minutes.

4. Run the health check:

```bash
bash scripts/health-check.sh
```

All lines must show OK. If the VPN line shows FAIL, make sure the WireGuard keys in `.env` are correct.

### Set up the Emby libraries

1. Open http://localhost:8096.
2. Complete the setup wizard. Select a language. Create an administrator account.
3. Add a Movies library:
   - Content type: Movies
   - Folder: `/data/movies`
4. Add a TV library:
   - Content type: TV Shows
   - Folder: `/data/tvshows`
5. Finish the wizard. Emby scans the folders by itself.

### Connect the services

Run the configuration script one time:

```bash
bash scripts/configure.sh
```

The script does these tasks:

- It adds rTorrent as the download client in Radarr and Sonarr.
- It adds the search indexers.
- It connects Prowlarr, Radarr, Sonarr, and Seerr.
- It asks you to sign in to Seerr with your Emby account. This step uses your browser.

The script saves the API keys in `<MEDIA_DIR>/state/first-run-credentials.txt`. The default path is `~/Media/state/first-run-credentials.txt`. Only you can read this file.

### Install the auto-healer (recommended)

The auto-healer checks the stack every hour. It restarts the VPN or a container that stopped.

```bash
bash scripts/install-auto-heal.sh
```

The log file is `~/Library/Logs/media-stack/auto-heal.log`.

To remove the auto-healer:

```bash
launchctl unload ~/Library/LaunchAgents/com.media-stack.auto-heal.plist
rm ~/Library/LaunchAgents/com.media-stack.auto-heal.plist
```

The setup is now complete.

---

## 6. Day-to-day use

### Request and watch media

1. Open Seerr at http://localhost:5055.
2. Search for a movie or a TV show.
3. Select "Request".
4. Wait for the download. The stack imports the file by itself.
5. Open Emby at http://localhost:8096 to watch.

### What the stack does by itself

- It searches for and downloads each request.
- It imports finished downloads into Emby.
- It gets English subtitles.
- It starts again after a Mac restart. OrbStack or Docker Desktop must start at login.
- It updates itself at 04:00 each day, if you turn on auto-update. See [Update the stack](#update-the-stack).

### Start and stop the stack

```bash
cd ~/mac-media-stack
docker compose down      # stop
docker compose up -d     # start
```

### Update the stack

To get the newest release, run:

```bash
bash scripts/update-to-latest-release.sh
docker compose up -d
```

To have the stack do this by itself every day at 04:00, turn on auto-update:

```bash
bash scripts/install-auto-update.sh
```

Auto-update moves the stack to the newest release. A release names the exact image versions it was tested with, so the apps only change when a new release is published. Keep these points in mind:

- It skips its run if you edited a tracked file or made commits of your own in this folder. Your `.env` is safe.
- When it does run, it resets the project files to the release. Your changes to files such as `docker-compose.yml` are lost.
- Containers restart when their image changes, so a running download pauses for a moment.

The log file is `~/Library/Logs/media-stack/auto-update.log`.

To remove auto-update:

```bash
launchctl unload ~/Library/LaunchAgents/com.media-stack.auto-update.plist
rm ~/Library/LaunchAgents/com.media-stack.auto-update.plist
```

### About the torrent client

rTorrent is the torrent client. It runs behind the VPN. Flood is its web page.

- **Download folders.** rTorrent downloads into `downloads/temp`. It then moves finished files to `downloads/complete/radarr` or `downloads/complete/tv-sonarr`. It seeds from there.
- **Import.** Radarr and Sonarr import files with a hardlink. The file uses disk space one time only. Refer to [About hardlinks](#about-hardlinks).
- **Seeding.** Radarr and Sonarr do not remove finished torrents. Remove them yourself in Flood when you are done.
- **Seed limits.** Set the ratio and time limits for each indexer in Prowlarr.
- **Port forwarding.** With ProtonVPN, the stack gives the forwarded port to rTorrent each time the VPN connects. If you restart only the `rtorrent` container, also restart `gluetun`.
- **Port 8000.** rTorrent uses port 8000. Gluetun uses port 8010 for its control server.

### About hardlinks

A hardlink is a second name for one file. Both names point to the same data on the disk. The data uses disk space one time only.

```
downloads/complete/radarr/Movie.mkv   -->  data on the disk (20 GB)
movies/Movie (2024)/Movie.mkv         -->  the same data
```

- rTorrent seeds the file from the name in `downloads`.
- Emby reads the file from the name in `movies`.
- If you delete one name, the other name stays.
- The disk space becomes free only after you delete the last name.

**How the stack makes hardlinks possible**

A hardlink works only inside one file system. In a container, both paths must also be in one mount.

- Radarr, Sonarr, and Bazarr mount `MEDIA_DIR` as `/data`. The folders `downloads`, `movies`, and `tvshows` are all inside this one mount. The `docker-compose.yml` file sets this mount.
- The root folders in Radarr and Sonarr are `/data/movies` and `/data/tvshows`.
- rTorrent mounts only the `downloads` folder as `/downloads`. It does not import files, so it does not need the full mount.
- `scripts/configure.sh` adds a remote path mapping in Radarr and Sonarr. It maps `/downloads/` to `/data/downloads/`. With this mapping, the apps find the files that rTorrent reports.
- Emby mounts `movies` and `tvshows` as separate folders. This is correct because Emby only reads the files.

> **WARNING**
> Do not give `downloads` and the library separate mounts. Separate mounts force Radarr and Sonarr to copy each file.

**The setting in Radarr and Sonarr**

Radarr and Sonarr have a setting named "Use Hardlinks instead of Copy". It is on by default. The stack does not change it.

1. In Radarr or Sonarr, open Settings, then Media Management.
2. Find "Use Hardlinks instead of Copy". If you cannot see it, select "Show Advanced".
3. Make sure that the setting is on.

If this setting is off, the apps copy each file. The apps also copy each file when `downloads` and the library are on different file systems. Radarr and Sonarr do not show an error in the web page when they copy.

**Check that hardlinks work**

1. Wait for Radarr to import a movie.
2. Run this command. Replace `~/Media` with your `MEDIA_DIR`:

```bash
find ~/Media/downloads/complete ~/Media/movies -name "*.mkv" -exec ls -li {} +
```

3. Find the movie in the list. It shows two files.
4. Compare the number in the first column of each file. This number is the inode. The inode is the record that holds the data of a file.
5. If the two numbers are the same, the files are hardlinks. The number in the third column is 2 or more.
6. If the two numbers are different, the apps copied the file. Do the steps in the table in [Troubleshooting](#7-troubleshooting).

### Friendly hostnames (optional)

Friendly hostnames replace addresses such as `localhost:7878`. Each web page gets a name:

| Name | Page |
|------|------|
| `media.lan` | A list of all pages |
| `seerr.media.lan` | Seerr |
| `emby.media.lan` | Emby |
| `radarr.media.lan` | Radarr |
| `sonarr.media.lan` | Sonarr |
| `prowlarr.media.lan` | Prowlarr |
| `bazarr.media.lan` | Bazarr |
| `flood.media.lan` | Flood |
| `rutorrent.media.lan` | ruTorrent |

A Caddy container listens on port 80. It sends each request to the correct container, based on the name. The `localhost` addresses continue to work on this Mac.

**Turn on hostnames**

1. Use `bash bootstrap.sh --proxy`. Or add these lines to `.env`:

```
PROXY_DOMAIN=media.lan
COMPOSE_FILE=docker-compose.yml:docker-compose.proxy.yml
```

2. Make the names resolve. Choose one method:
   - **This Mac only.** Run `bash scripts/setup-hosts.sh`. Enter your password when the script asks for it. To undo, run `bash scripts/setup-hosts.sh --remove`.
   - **Your router.** Do not run `setup-hosts.sh`. Follow the steps below.
3. Run `docker compose up -d`.

Use `.lan` or `.home.arpa` for the domain. Do not use `.local`. macOS uses `.local` for network discovery.

**Use the DNS of a UniFi router**

All devices on your network, including this Mac, then use the names. The file `/etc/hosts` does not change.

1. Give this Mac a fixed IP address. In the UniFi Network app, open Client Devices, select this Mac, and set "Fixed IP Address".
2. In `.env`, set `PROXY_BIND_IP=0.0.0.0`. With the default `127.0.0.1`, other devices cannot connect.
3. In UniFi, open Settings, then Routing, then DNS. In newer versions, open Policies, then DNS.
4. Add one A record for each name in the table above. Point every record to the fixed IP address of this Mac. If your UniFi version accepts `*.media.lan`, one record is sufficient.
5. Run `docker compose up -d`.
6. Open http://media.lan.

> **NOTE**
> Each record must point to the LAN IP address of the Mac. Do not use `127.0.0.1`. The domain must be the same as `PROXY_DOMAIN` in `.env`.

### Media on a NAS (optional)

Radarr and Sonarr import files with a hardlink. A hardlink works only when `downloads` and the library are on the same file system.

> **WARNING**
> macOS SMB shares do not support hardlinks. The stack then copies each file. This uses double the disk space. Use NFS.

1. Mount the share with NFS:

```bash
mkdir -p ~/nas
sudo mount_nfs -o resvport <nas-ip>:<export-path> ~/nas
```

2. Test the mount:

```bash
cd ~/nas && mkdir .ht && echo hi > .ht/a && ln .ht/a .ht/b && ls -li .ht; rm -rf .ht
```

3. Make sure that both files show the same inode number.
4. In `.env`, set `MEDIA_DIR` to the mount. Set `CONFIG_DIR` to a local folder:

```
MEDIA_DIR=/Users/you/nas
CONFIG_DIR=/Users/you/mac-media-stack-config
```

5. Make sure that the folders on the share are `downloads`, `movies`, and `tvshows`. The names are case-sensitive.
6. Mount the share each time before you start the stack. A `mount_nfs` mount does not survive a restart.

### Move from an older version

Older versions used the folders `Downloads`, `Movies`, and `TV Shows`. They also mounted `/downloads`, `/movies`, and `/tv` as separate volumes. This forces copies. The current version uses lowercase folder names and one `/data` volume. To move to the new layout:

1. Stop the stack. Run `docker compose down`.
2. Rename the folders in your media folder. Replace `~/Media` with your `MEDIA_DIR`:

```bash
cd ~/Media
mv "TV Shows" tvshows
mv Movies movies
mv Downloads downloads
```

3. Update the stack. Run `docker compose up -d`.
4. Run `bash scripts/configure.sh` again. It adds the new root folders.
5. In Radarr, open the Mass Editor. Set the root folder to `/data/movies`. Select "Move files".
6. In Sonarr, do the same with `/data/tvshows`.
7. In Seerr, open Settings, then Services. Set the same root folders for Radarr and Sonarr.
8. In Bazarr, use the new `/data/...` paths. Bazarr reads the paths from Radarr and Sonarr.
9. Let the existing torrents finish. You can also move them to `/data/downloads/complete/...`.

> **NOTE**
> On a default Mac disk, `Movies` and `movies` are the same folder. The `mv` commands for these two folders can show an error. Ignore it. The `TV Shows` rename is always necessary.

---

## 7. Troubleshooting

First, run the health check:

```bash
bash scripts/health-check.sh
```

Then find your problem in the table.

| Problem | Cause | Action |
|---------|-------|--------|
| Nothing works after a restart | The container runtime is not ready | Open OrbStack or Docker Desktop. Wait 30 seconds. Run the health check. |
| The VPN check fails | The WireGuard keys are wrong | Make sure the keys in `.env` are correct and have no spaces. Run `docker compose restart gluetun`. |
| Downloads are stuck or slow | The VPN tunnel is down | Open Flood at http://localhost:3000. If all torrents show "stalled", run `docker compose restart gluetun`. |
| Emby does not show a new movie | The library did not scan yet | In Emby, open the library. Select "Scan Library". Make sure the folder paths are `/data/movies` and `/data/tvshows`. |
| "Permission denied" | `PUID` or `PGID` is wrong | Run `id -u` and `id -g`. Put the values in `.env`. Run `docker compose up -d`. |
| A hostname does not open | The name does not resolve | Run `bash scripts/doctor.sh`. Refer to the actions below. |
| Files are copied and not linked | The media is on an SMB share, or "Use Hardlinks instead of Copy" is off | Use NFS. Refer to [Media on a NAS](#media-on-a-nas-optional). Make sure that the setting is on. Refer to [About hardlinks](#about-hardlinks). |

**If a hostname does not open:**

1. Run `bash scripts/setup-hosts.sh`, or add the DNS records on your router.
2. For router DNS, make sure that each record points to the LAN IP address of the Mac.
3. Make sure that `PROXY_BIND_IP=0.0.0.0` is in `.env`.
4. Make sure that the domain is the same as `PROXY_DOMAIN`.
5. After a change to `.env`, run `docker compose up -d`.

**If you need help:**

1. Run `bash scripts/health-check.sh`.
2. Send the output to the person who set up the stack.
