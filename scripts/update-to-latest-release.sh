#!/bin/bash
# Update an existing clone to the latest tagged release (vX.Y.Z).
# Safe by default: refuses to run with tracked local changes or local commits ahead of upstream.
# Usage: bash scripts/update-to-latest-release.sh [--yes] [--force] [--skip-setup]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/ui.sh
source "$SCRIPT_DIR/lib/ui.sh"

ASSUME_YES=false
FORCE=false
SKIP_SETUP=false

usage() {
    cat <<EOF
Usage: bash scripts/update-to-latest-release.sh [OPTIONS]

Updates this clone to the latest Git tag that matches v*.

Options:
  --yes         Skip confirmation prompt
  --force       Allow resetting when local branch is ahead of upstream
  --skip-setup  Do not run scripts/setup.sh after updating
  --help        Show this help message
EOF
}

fail() { ui_fail "$1"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)
            ASSUME_YES=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
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

command -v git >/dev/null 2>&1 || fail "git not found"

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$PROJECT_DIR" ]] || fail "Not inside a git repository"
cd "$PROJECT_DIR"

origin_url="$(git remote get-url origin 2>/dev/null || true)"
[[ -n "$origin_url" ]] || fail "origin remote not configured"

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    fail "Tracked local changes detected. Commit/stash first, or rerun with --force."
fi

current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
if [[ -n "$current_branch" ]]; then
    upstream="$(git for-each-ref --format='%(upstream:short)' "refs/heads/$current_branch" | head -1)"
    if [[ -n "$upstream" ]]; then
        ahead_count="$(git rev-list --count "$upstream..$current_branch")"
        if [[ "$ahead_count" -gt 0 && "$FORCE" != true ]]; then
            fail "Branch '$current_branch' has $ahead_count local commit(s) ahead of upstream. Rerun with --force to reset."
        fi
    fi
fi

ui_info "Fetching tags from origin..."
git fetch origin --tags --prune >/dev/null

latest_tag="$(git tag -l 'v*' --sort=-version:refname | head -1)"
[[ -n "$latest_tag" ]] || fail "No release tags matching v* were found"

target_sha="$(git rev-list -n1 "$latest_tag")"
current_sha="$(git rev-parse HEAD)"

echo ""
echo "Repo:         $PROJECT_DIR"
echo "Origin:       $origin_url"
echo "Current ref:  ${current_branch:-detached}"
echo "Current SHA:  $current_sha"
echo "Latest tag:   $latest_tag"
echo "Target SHA:   $target_sha"
echo ""

if [[ "$current_sha" == "$target_sha" ]]; then
    ui_ok "Already on latest release ($latest_tag)"
else
    if [[ "$ASSUME_YES" != true ]]; then
        read -r -p "Update this clone to $latest_tag? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    if [[ -z "$current_branch" ]]; then
        ui_warn "Detached HEAD detected. Checking out 'main' before reset."
        if git show-ref --verify --quiet refs/heads/main; then
            git checkout main >/dev/null
        else
            git checkout -b main >/dev/null
        fi
        current_branch="main"
    fi

    git reset --hard "$target_sha" >/dev/null
    ui_ok "Updated $current_branch to $latest_tag"
fi

if [[ "$SKIP_SETUP" != true && -x scripts/setup.sh ]]; then
    # The updated checkout provides the config module, so load it only now.
    # shellcheck source=scripts/lib/stack-config.sh
    source scripts/lib/stack-config.sh
    media_dir="$(config_get_path MEDIA_DIR)"
    ui_info "Running setup sync (scripts/setup.sh)"
    if [[ -n "$media_dir" ]]; then
        bash scripts/setup.sh --media-dir "$media_dir" >/dev/null
    else
        bash scripts/setup.sh >/dev/null
    fi
    ui_ok "Setup sync complete"
fi

echo ""
echo "Update complete."
echo "Next steps:"
echo "  1. Review .env if new keys were added"
echo "  2. Restart stack: docker compose up -d"
echo "  3. Verify: bash scripts/health-check.sh"
