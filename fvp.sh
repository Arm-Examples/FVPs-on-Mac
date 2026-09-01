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

# Publish any GDBServer plugin port to localhost.
for flag in "${FLAGS[@]}"; do
    if [[ "$flag" =~ ^GDBServer\.port=([0-9]+)$ ]]; then
        gdb_port="${BASH_REMATCH[1]}"
        PORTS+=("-p" "127.0.0.1:${gdb_port}:${gdb_port}")
    fi

    # Publish explicitly configured FVP terminal ports for host UART clients.
    if [[ "$flag" =~ ^[^=]*telnetterminal[0-9]+\.start_port=([0-9]+)$ ]]; then
        uart_port="${BASH_REMATCH[1]}"
        PORTS+=("-p" "127.0.0.1:${uart_port}:${uart_port}")
    fi
done


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

# Track the exact container created by this wrapper invocation.
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/fvp-wrapper.XXXXXX")"
cidfile="${runtime_dir}/container.cid"
docker_pid=""

cleanup() {
    local status="$1"
    local container_id=""

    # Prevent recursive traps while cleaning up.
    trap - INT TERM HUP

    if [[ -s "${cidfile}" ]]; then
        container_id="$(<"${cidfile}")"

        # Request graceful termination, then force removal if necessary.
        docker stop --time 2 "${container_id}" >/dev/null 2>&1 || true
        docker rm -f "${container_id}" >/dev/null 2>&1 || true
    fi

    # Reap the local docker client process.
    if [[ -n "${docker_pid}" ]]; then
        kill "${docker_pid}" >/dev/null 2>&1 || true
        wait "${docker_pid}" 2>/dev/null || true
    fi

    rm -f "${cidfile}" 2>/dev/null || true
    rmdir "${runtime_dir}" 2>/dev/null || true

    exit "$status"
}

trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP

docker run --rm \
  --cidfile "$cidfile" \
  "${PORTS[@]}" \
  "${MOUNTS[@]}" \
  --workdir "$workdir" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  --env "DISPLAY=${DISPLAY_IP}:0" \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}" &

docker_pid=$!
wait "${docker_pid}"
result=$?

cleanup "${result}"