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

docker run \
  "${PORTS[@]}" \
  --mount "type=bind,src=${HOME},dst=${HOME}" \
  --workdir "$(pwd)" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  --env DISPLAY=${DISPLAY_IP}:0 \
  --volume /tmp/.X11-unix:/tmp/.X11-unix \
  "fvp:${FVP_VERSION}" "${MODEL}" "${FLAGS[@]}"

exit
