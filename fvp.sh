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

# Mount home directory by default unless explicitly disabled or custom workdir is set
if [ "$FVP_DISABLE_HOME_MOUNT" != "true" ] && [ -z "$FVP_MAC_WORKDIR" ]; then
    echo "Warning: FVPs-on-Mac container is mounting entire home directory. For improved performance and security, consider setting FVP_DISABLE_HOME_MOUNT=true or FVP_MAC_WORKDIR to limit mounted directories." >&2
    MOUNTS+=("--mount" "type=bind,src=${HOME},dst=${HOME}")
else
    MOUNTS+=("--mount" "type=bind,src=${HOME}/.armlm/,dst=${HOME}/.armlm/")
fi

# Set working directory
WORKDIR="$(pwd)"

# Handle custom workdir if specified
if [ -n "$FVP_MAC_WORKDIR" ]; then
    if [ ! -d "$FVP_MAC_WORKDIR" ]; then
        echo "Error: FVP_MAC_WORKDIR path '$FVP_MAC_WORKDIR' does not exist or is not a directory" >&2
        exit 1
    fi
    MOUNTS+=("--mount" "type=bind,src=${FVP_MAC_WORKDIR},dst=${FVP_MAC_WORKDIR}")
    WORKDIR="$FVP_MAC_WORKDIR"
elif [ "$FVP_DISABLE_HOME_MOUNT" == "true" ]; then
    WORKDIR="$HOME"
else
    # Validate current directory is under $HOME when home is mounted
    case "$WORKDIR" in
        "$HOME"*) ;;
        *) 
            echo "Error: Current directory '$WORKDIR' is not under home directory '$HOME' and will not be accessible by the FVP." >&2
            echo "Either change to a directory under $HOME, set FVP_MAC_WORKDIR to specify a different mount," >&2
            echo "or set FVP_DISABLE_HOME_MOUNT=true to improve security and performance if you don't need home directory access" >&2
            exit 1
            ;;
    esac
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
