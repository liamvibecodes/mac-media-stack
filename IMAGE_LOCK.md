# Image Lock Matrix

This stack is pinned to exact image digests in `docker-compose.yml` for reproducible installs.

Tested lock snapshot:
- Date: `2026-02-22`
- Docker Engine: `29.2.1`
- Platform: `aarch64 (Docker Desktop)`

| Service | Locked Image |
|---|---|
| bazarr | `lscr.io/linuxserver/bazarr@sha256:1cf40186b1bc35bec87f4e4892d5d8c06086da331010be03e3459a86869c5e74` |
| flaresolverr | `ghcr.io/flaresolverr/flaresolverr@sha256:7962759d99d7e125e108e0f5e7f3cdbcd36161776d058d1d9b7153b92ef1af9e` |
| gluetun | `qmcgaw/gluetun@sha256:495cdc65ace4c110cf4de3d1f5f90e8a1dd2eb0f8b67151d1ad6101b2a02a476` |
| radarr | `lscr.io/linuxserver/radarr@sha256:6d3e68474ea146f995af98d3fb2cb1a14e2e4457ddaf035aa5426889e2f9249c` |
| sonarr | `lscr.io/linuxserver/sonarr@sha256:37be832b78548e3f55f69c45b50e3b14d18df1b6def2a4994258217e67efb1a1` |
| prowlarr | `lscr.io/linuxserver/prowlarr@sha256:e74a1e093dcc223d671d4b7061e2b4946f1989a4d3059654ff4e623b731c9134` |
| seerr | `ghcr.io/seerr-team/seerr@sha256:d8fab675b55ad293ded98fd71efcfd46054cbad9746534ae1cc4794a88c0b3be` |
| emby | `lscr.io/linuxserver/emby@sha256:4c3d0b88b7d8b79ee656ff016fd049b51585753ddbb9db984d6c230c39b4df74` |
| rtorrent | `crazymax/rtorrent-rutorrent@sha256:a6577938d9b2d1e9038a9989c395990738c984ff6d7a2037a082a06bb4ab8a2d` |
| flood | `jesec/flood@sha256:241f172786fe958a09a55615cb4cd1b15d0aec9751f2d87dd8d7a67bcd24f0fa` |
| caddy (optional) | `caddy@sha256:36c24ad91a7ff7bc4c87fe22bfa8df3c4b18da0773d73fc12ee2c52b98c0bb7e` |

## Updating The Lock

Run:
```bash
bash scripts/refresh-image-lock.sh
```

Then smoke test the stack and commit the updated lock files.
