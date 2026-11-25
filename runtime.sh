#!/usr/bin/env bash

# Sourced by the build, model, and license wrappers. Setup records the choice;
# model and license commands never prompt (including VS Code launches).
FVP_RUNTIME_CHOICE_FILE="${FVP_RUNTIME_CHOICE_FILE:-$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.fvp-runtime}"

fvp_select_runtime() {
    local mode="${1:-use}" has_docker=0 has_container=0 choice=""
    command -v docker >/dev/null 2>&1 && has_docker=1
    command -v container >/dev/null 2>&1 && has_container=1

    if [[ -n "${FVP_RUNTIME:-}" ]]; then
        choice="${FVP_RUNTIME}"
    elif (( has_docker && has_container )); then
        if [[ -f "${FVP_RUNTIME_CHOICE_FILE}" ]]; then
            IFS= read -r choice < "${FVP_RUNTIME_CHOICE_FILE}" || true
        else
            if [[ "${mode}" != setup ]]; then
                echo "Both Docker and Apple Container are installed. Run ./build.sh in a terminal to choose one, or set FVP_RUNTIME=docker|container." >&2
                return 1
            fi
            if ! ( : </dev/tty ) 2>/dev/null; then
                echo "Both Docker and Apple Container are installed. Run ./build.sh in a terminal to choose one, or set FVP_RUNTIME=docker|container." >&2
                return 1
            fi
            while :; do
                if ! printf 'Use Docker or Apple Container for FVPs? [docker/container]: ' > /dev/tty; then
                    echo "Could not write to the terminal. Set FVP_RUNTIME=docker|container and rerun ./build.sh." >&2
                    return 1
                fi
                IFS= read -r choice < /dev/tty || return 1
                case "${choice}" in
                    docker|container) break ;;
                    *) printf 'Enter docker or container.\n' > /dev/tty ;;
                esac
            done
        fi
    elif (( has_docker )); then
        choice=docker
    elif (( has_container )); then
        choice=container
    else
        echo "Neither Docker nor Apple Container CLI is installed." >&2
        return 1
    fi

    case "${choice}" in
        docker)
            if (( ! has_docker )); then
                echo "Docker CLI is not installed. Install Docker or choose FVP_RUNTIME=container." >&2
                return 1
            fi
            ;;
        container)
            if (( ! has_container )); then
                echo "Apple Container CLI is not installed. Install it or choose FVP_RUNTIME=docker." >&2
                return 1
            fi
            ;;
        *)
            echo "Invalid FVP runtime '${choice}'. Use docker or container." >&2
            return 1
            ;;
    esac
    if [[ "${mode}" == setup ]]; then
        if ! printf '%s\n' "${choice}" > "${FVP_RUNTIME_CHOICE_FILE}"; then
            echo "Could not save the runtime choice in ${FVP_RUNTIME_CHOICE_FILE}; set FVP_RUNTIME for later commands." >&2
            return 1
        fi
    fi
    export FVP_RUNTIME="${choice}"
}

fvp_require_runtime_ready() {
    case "${FVP_RUNTIME}" in
        docker)
            if ! docker info >/dev/null 2>&1; then
                echo "Docker is not running. Start Docker Desktop and retry." >&2
                return 1
            fi
            ;;
        container)
            if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
                echo "Apple Container requires an Apple silicon Mac." >&2
                return 1
            fi
            if ! container system status >/dev/null 2>&1; then
                echo "Apple Container is not running. Start it with: container system start" >&2
                return 1
            fi
            ;;
    esac
}
