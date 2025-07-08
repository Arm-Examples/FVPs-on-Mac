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


# Set PRIMARY_MOUNT_DIR from environment variable or default to pwd
PRIMARY_MOUNT_DIR="${FVP_MAC_PRIMARY_MOUNT_DIR:-$(pwd)}"
# Set WORKDIR from environment variable or default to PRIMARY_MOUNT_DIR
WORKDIR="${FVP_MAC_WORK_DIR:-$PRIMARY_MOUNT_DIR}"

# Mount licenses
MOUNTS=("--mount" "type=bind,src=${HOME}/.armlm/,dst=${HOME}/.armlm/")
# Primary mount
MOUNTS+=("--mount" "type=bind,src=${PRIMARY_MOUNT_DIR}/,dst=${PRIMARY_MOUNT_DIR}/")

docker run \
  "${PORTS[@]}" \
  "${MOUNTS[@]}" \
  --workdir "$WORKDIR" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  --env DISPLAY=${DISPLAY_IP}:0 \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}"

exit
