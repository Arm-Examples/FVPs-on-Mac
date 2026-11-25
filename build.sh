#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/fvprc"
source "$(dirname "$0")/runtime.sh"
fvp_select_runtime setup
fvp_require_runtime_ready

if [[ ! -d "${HOME}/.armlm" ]]; then
    echo "No Arm license cache found at ~/.armlm. Activate a user-based license with bin/armlm." >&2
fi

cd "$(dirname "$0")"

build_args=()
run_args=(--rm)
if [[ "${FVP_RUNTIME}" == container ]]; then
    run_args+=(--progress none)
    if [[ -n "${FVP_CONTAINER_DNS}" ]]; then
        build_args+=(--dns "${FVP_CONTAINER_DNS}")
        run_args+=(--dns "${FVP_CONTAINER_DNS}")
    fi
fi

"${FVP_RUNTIME}" build -t "fvp:${FVP_VERSION}" \
    -f Containerfile \
    "${build_args[@]}" \
    --build-arg "FVP_VERSION=${FVP_VERSION}" \
    --build-arg "FVP_BASE_URL=${FVP_BASE_URL}" \
    --build-arg "FVP_ARCHIVE=${FVP_ARCHIVE}" \
    --build-arg "FVP_SHA256=${FVP_SHA256}" \
    --build-arg "USER=$(whoami)" \
    --build-arg "USERID=$(id -u)" \
    "$@" .

mkdir -p bin
models_file="$(mktemp "${TMPDIR:-/tmp}/fvp-models.XXXXXX")"
trap 'rm -f "${models_file}"' EXIT

"${FVP_RUNTIME}" run "${run_args[@]}" "fvp:${FVP_VERSION}" \
    find -L /opt/avh-fvp/bin/ -maxdepth 1 -name 'FVP_*' -type f -executable -print0 > "${models_file}"

if [[ ! -s "${models_file}" ]]; then
    echo "No executable FVP models found in the built image." >&2
    exit 1
fi

while IFS= read -r -d '' model; do
    model="$(basename "${model}")"
    if [[ ! -L "bin/${model}" ]]; then
        ln -s ../fvp.sh "bin/${model}"
    fi
done < "${models_file}"

if [[ ! -L bin/armlm ]]; then
    ln -s ../armlm.sh bin/armlm
fi
