#!/usr/bin/env bash

MODEL="$(basename "$0")"
DIRNAME="$(dirname "$(realpath "$0")")"

source "${DIRNAME}/fvprc"

FLAGS=()
PORTS=()
DISPLAY_IP="docker.for.mac.host.internal"

while [[ $# -gt 0 ]]; do
    case $1 in
        --display-ip)
            DISPLAY_IP="$2"
            shift 2
            ;;
        *)
            FLAGS+=("$1")
            shift
            ;;
    esac
done

if [[ "${FLAGS[*]}" =~ "-I" || "${FLAGS[*]}" =~ "--iris-server" ]]; then
    PORTS+=("-p" "7100:7100")
    if [[ ! "${FLAGS[*]}" =~ "--print-port-number" && ! "${FLAGS[*]}" =~ "-p" ]]; then
        FLAGS+=("--print-port-number")
    fi
    if [[ ! "${FLAGS[*]}" =~ "--iris-allow-remote" && ! "${FLAGS[*]}" =~ "-A" ]]; then
        FLAGS+=("--iris-allow-remote")
    fi
fi

if ! docker image inspect "fvp:${FVP_VERSION}" >/dev/null 2>&1; then
    "${DIRNAME}/build.sh"
fi

# Define the default mounts
MOUNTS=()

# Mount home directory by default unless explicitly disabled
if [ "$FVP_DISABLE_HOME_MOUNT" != "true" ]; then
    MOUNTS+=("--mount" "type=bind,src=${HOME},dst=${HOME}")
else
    # If home mounting is disabled, still mount the license directory
    MOUNTS+=("--mount" "type=bind,src=${HOME}/.armlm/,dst=${HOME}/.armlm/")
fi


WORKDIR="$(pwd)"
if [ -n "$FVP_MAC_WORKDIR" ]; then
    # Add the FVP_MAC_WORKDIR mount if the variable is set
    if [ -d "$FVP_MAC_WORKDIR" ]; then
        MOUNTS+=("--mount" "type=bind,src=${FVP_MAC_WORKDIR},dst=${FVP_MAC_WORKDIR}")
        WORKDIR="$FVP_MAC_WORKDIR"
    else
        echo "Error: FVP_MAC_WORKDIR path '$FVP_MAC_WORKDIR' does not exist or is not a directory" >&2
        exit 1
    fi
else
    if [ "$FVP_DISABLE_HOME_MOUNT" == "true" ]; then
        # Only license dir is mounted, so pwd won't work, revert to $HOME
        WORKDIR="$HOME"
    else
        # Check if current directory is under $HOME when home is mounted
        case "$WORKDIR" in
            "$HOME"*) ;;  # WORKDIR is under $HOME, continue
            *) 
                echo "Error: Current directory '$WORKDIR' is not under home directory '$HOME'" >&2
                echo "Either change to a directory under $HOME or set FVP_MAC_WORKDIR to specify a different mount" >&2
                exit 1
                ;;
        esac
    fi
fi

docker run \
  "${PORTS[@]}" \
  "${MOUNTS[@]}" \
  --workdir "$WORKDIR" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  --env DISPLAY=${DISPLAY_IP}:0 \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}"

exit
