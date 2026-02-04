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


# Set mount_dir from environment variable or default to home
mount_dir="${FVP_MOUNT_DIR:-$HOME}"

# Validate mount_dir exists and is a directory
if [[ ! -d "$mount_dir" ]]; then
    echo "Error: FVP_MOUNT_DIR '$mount_dir' is not a valid directory" >&2
    exit 1
fi

# Set workdir from environment variable or default to pwd
workdir="${FVP_WORKDIR:-$(pwd)}"

# Validate workdir exists if it's a subdirectory of mount_dir
if [[ "$workdir" == "$mount_dir"* && ! -d "$workdir" ]]; then
    echo "Error: FVP_WORKDIR '$workdir' is not a valid directory" >&2
    exit 1
fi

# Mount licenses
MOUNTS=(
    "--mount" "type=bind,src=${HOME}/.armlm/,dst=${HOME}/.armlm/"
    "--mount" "type=bind,src=${mount_dir}/,dst=${mount_dir}/"
)

docker run \
  "${PORTS[@]}" \
  "${MOUNTS[@]}" \
  --workdir "$workdir" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  --env "DISPLAY=${DISPLAY_IP}:0" \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}"

exit
