# Contributing

Thanks for your interest in contributing to Mac Media Stack.

## How to Help

- **Bug reports**: Open an issue with your macOS version, Docker version, and the output of `bash scripts/health-check.sh`.
- **Feature requests**: Open an issue describing what you'd like and why.
- **Pull requests**: Fork the repo, make your changes on a branch, and open a PR. Keep changes focused on one thing.

## Guidelines

- Test your changes on a clean macOS install if possible.
- Don't commit `.env` files, API keys, or any credentials.
- Keep scripts compatible with both Intel and Apple Silicon Macs.
- Match the existing code style (bash scripts use `set -e`, consistent formatting).

## Code structure

Scripts share a few modules in `scripts/lib/`. Use them instead of re-implementing the logic:

- `stack-config.sh`: read and write `.env` (`config_get`, `config_set`) and the install choices. Never `source .env` or `sed` it directly.
- `topology.sh`: which containers and web UIs the stack has for the current configuration. Add new containers to its table, not to individual scripts.
- `vpn.sh`: asks gluetun whether the tunnel is up.
- `ui.sh`: colours, OK/WARN/FAIL lines and `wait_for_service`.
- `arr.sh`: Radarr/Sonarr API operations used by `configure.sh`.

Run the tests with `bash tests/run.sh`. They need no Docker; they fake `docker` and the HTTP calls.
New behaviour in a module should come with a test next to the existing ones in `tests/`.
Domain terms are defined in `GLOSSARY.md`.

## Questions?

Open an issue. There are no dumb questions.
