#!/bin/bash
# Shared container runtime detection helpers.

detect_installed_runtime() {
    local has_orbstack=0
    local has_docker_desktop=0

    if [[ -d "/Applications/OrbStack.app" ]] || command -v orbstack &>/dev/null; then
        has_orbstack=1
    fi
    if [[ -d "/Applications/Docker.app" ]]; then
        has_docker_desktop=1
    fi

    if [[ $has_orbstack -eq 1 && $has_docker_desktop -eq 1 ]]; then
        echo "OrbStack or Docker Desktop"
    elif [[ $has_orbstack -eq 1 ]]; then
        echo "OrbStack"
    elif [[ $has_docker_desktop -eq 1 ]]; then
        echo "Docker Desktop"
    else
        echo "none"
    fi
}

detect_running_runtime() {
    local os_name
    os_name=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)
    if [[ "$os_name" == *"OrbStack"* ]]; then
        echo "OrbStack"
    elif [[ "$os_name" == *"Docker Desktop"* ]]; then
        echo "Docker Desktop"
    else
        echo "Docker"
    fi
}
