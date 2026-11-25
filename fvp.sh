#!/usr/bin/env bash

MODEL="$(basename "$0")"
DIRNAME="$(dirname "$(realpath "$0")")"

source "${DIRNAME}/fvprc"
source "${DIRNAME}/runtime.sh"
fvp_select_runtime || exit $?
fvp_require_runtime_ready || exit $?

FLAGS=()
PORTS=()
DISPLAY_IP="${FVP_DISPLAY_IP:-}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --display-ip)
            if [[ $# -lt 2 ]]; then
                echo "Error: --display-ip requires an address" >&2
                exit 2
            fi
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
    PORTS+=("-p" "127.0.0.1:7100:7100")
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


if ! "${FVP_RUNTIME}" image inspect "fvp:${FVP_VERSION}" >/dev/null 2>&1; then
    "${DIRNAME}/build.sh" || exit $?
fi


# Set mount_dir from environment variable or default to home
mount_dir="${FVP_MOUNT_DIR:-$HOME}"

# Validate mount_dir exists and is a directory
if [[ ! -d "$mount_dir" ]]; then
    echo "Error: FVP_MOUNT_DIR '$mount_dir' is not a valid directory" >&2
    exit 1
fi
mount_dir="$(realpath "$mount_dir")"

# Set workdir from environment variable or default to pwd
workdir="${FVP_WORKDIR:-$(pwd)}"

# The working directory must be visible at the same path inside the container.
if [[ ! -d "$workdir" ]]; then
    echo "Error: FVP_WORKDIR '$workdir' is not a valid directory" >&2
    exit 1
fi
workdir="$(realpath "$workdir")"
if [[ "$workdir" != "$mount_dir" && "$workdir" != "$mount_dir/"* ]]; then
    echo "Error: FVP_WORKDIR '$workdir' is outside FVP_MOUNT_DIR '$mount_dir'" >&2
    exit 1
fi

# Bind mounts preserve host paths used in FVP arguments and the license cache.
mkdir -p "${HOME}/.armlm"
license_dir="$(realpath "${HOME}/.armlm")"
MOUNTS=("--mount" "type=bind,source=${mount_dir},target=${mount_dir}")
if [[ "$license_dir" != "$mount_dir" && "$license_dir" != "$mount_dir/"* ]]; then
    MOUNTS+=("--mount" "type=bind,source=${license_dir},target=${license_dir}")
fi

DISPLAY_ENV=()
if [[ -z "$DISPLAY_IP" && "${FVP_RUNTIME}" == docker ]]; then
    DISPLAY_IP=docker.for.mac.host.internal
fi
if [[ -n "$DISPLAY_IP" ]]; then
    DISPLAY_ENV=("--env" "DISPLAY=${DISPLAY_IP}:0")
fi

# An explicit Xauthority file lets GUI models authenticate to XQuartz without
# opening access to every container IP. The file must already be visible inside
# one of the wrapper's bind mounts.
if [[ -n "${FVP_XAUTHORITY:-}" ]]; then
    if [[ ! -f "$FVP_XAUTHORITY" ]]; then
        echo "Error: FVP_XAUTHORITY '$FVP_XAUTHORITY' is not a file" >&2
        exit 1
    fi
    auth_file="$(realpath "$FVP_XAUTHORITY")"
    if [[ "$auth_file" != "$mount_dir/"* && "$auth_file" != "$license_dir/"* ]]; then
        echo "Error: FVP_XAUTHORITY '$auth_file' is outside the mounted directories" >&2
        exit 1
    fi
    DISPLAY_ENV+=("--env" "XAUTHORITY=${auth_file}")
fi

DNS_ARGS=()
if [[ "${FVP_RUNTIME}" == container && -n "${FVP_CONTAINER_DNS}" ]]; then
    DNS_ARGS=("--dns" "${FVP_CONTAINER_DNS}")
fi

# Track the exact container created by this wrapper invocation.
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/fvp-wrapper.XXXXXX")"
cidfile="${runtime_dir}/container.cid"
container_name="fvp-${BASHPID}-${RANDOM}"
container_pid=""

cleanup() {
    local status="$1"
    local container_id="${container_name}"

    # Prevent recursive traps while cleaning up.
    trap - INT TERM HUP

    if [[ -s "${cidfile}" ]]; then
        container_id="$(<"${cidfile}")"
    fi

    # Request graceful termination, then force removal if necessary.
    "${FVP_RUNTIME}" stop --time 2 "${container_id}" >/dev/null 2>&1 || true
    if [[ "${FVP_RUNTIME}" == docker ]]; then
        docker rm -f "${container_id}" >/dev/null 2>&1 || true
    else
        container delete --force "${container_id}" >/dev/null 2>&1 || true
    fi

    # Reap the local container client process.
    if [[ -n "${container_pid}" ]]; then
        kill "${container_pid}" >/dev/null 2>&1 || true
        wait "${container_pid}" 2>/dev/null || true
    fi

    rm -f "${cidfile}" 2>/dev/null || true
    rmdir "${runtime_dir}" 2>/dev/null || true

    exit "$status"
}

trap 'cleanup 130' INT
trap 'cleanup 143' TERM
trap 'cleanup 129' HUP

runtime_args=(
    --rm
    --name "$container_name"
    --cidfile "$cidfile"
    "${DNS_ARGS[@]}"
    "${PORTS[@]}"
    "${MOUNTS[@]}"
    --workdir "$workdir"
    --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm"
    "${DISPLAY_ENV[@]}"
)
if [[ "${FVP_RUNTIME}" == container ]]; then
    runtime_args=(--progress none "${runtime_args[@]}")
fi

if [[ -t 0 && -t 1 ]]; then
    # The VIO getch module needs a TTY and live stdin. Keep the client in the
    # foreground: an asynchronous shell command would receive /dev/null.
    "${FVP_RUNTIME}" run "${runtime_args[@]}" -it \
        "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}"
    result=$?
else
    "${FVP_RUNTIME}" run "${runtime_args[@]}" \
        "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}" &
    container_pid=$!
    wait "${container_pid}"
    result=$?
fi

cleanup "${result}"
