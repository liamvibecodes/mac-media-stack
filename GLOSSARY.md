# Mac Media Stack

A self-hosted media automation stack for macOS: requests flow through Seerr to the *arr apps, downloads run behind a VPN, and a media server plays the result.

## Language

**Stack**:
The full set of containers that make up one install.
_Avoid_: Deployment, environment

**Install choices**:
The options picked at install time: whether the Proxy is on, and the VPN provider. The Proxy is on or off on every run; an unspecified VPN provider leaves `.env` as it is, and only an explicit `--mullvad` changes it.
_Avoid_: Profile, flavour, variant

**Media server**:
The app that plays the library: Emby, running in Docker.
_Avoid_: Player, streaming server

**Torrent client**:
The app that downloads: rTorrent with its Flood web UI.
_Avoid_: Downloader

**VPN gateway**:
The gluetun container whose tunnel carries all torrent traffic.
_Avoid_: VPN container, tunnel (the tunnel is the connection, the gateway is the container)

**Proxy**:
The optional Caddy container that gives each web UI a friendly hostname such as `seerr.media.lan`.
_Avoid_: Reverse proxy, ingress

**Stack configuration**:
The values in `.env`, including which optional compose files are loaded.
_Avoid_: Settings, env vars

**Stack topology**:
Which containers and web UIs exist for the current Stack configuration, and where each answers.
_Avoid_: Service list, inventory

**Stack health**:
Whether each member of the Stack topology is running and, for web UIs, answering. Reported by `health-check.sh`, acted on by Auto-heal.
_Avoid_: Status, liveness

**Answers**:
A web UI answers when it responds with HTTP 200, 301, 302, 401 or 403. An auth challenge counts, because it means the app is running.
_Avoid_: Up, reachable

**Required / advisory**:
A web UI is required when the Stack is unhealthy without it; advisory when its absence is only reported (Emby may still be starting).

**Auto-heal**:
The hourly background job that restarts the VPN gateway and any stopped container in the Stack topology.
_Avoid_: Watchdog, self-healing

**First-run configuration**:
The one-time step that wires the apps together: root folders, download client, indexers, and Seerr's links to Radarr and Sonarr.
_Avoid_: Setup (setup only creates folders and `.env`)
