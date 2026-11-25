#!/usr/bin/env bash

set -euo pipefail

DIRNAME="$(dirname "$(realpath "$0")")"

source "${DIRNAME}/fvprc"
source "${DIRNAME}/runtime.sh"
fvp_select_runtime
fvp_require_runtime_ready

if ! "${FVP_RUNTIME}" image inspect "fvp:${FVP_VERSION}" >/dev/null 2>&1; then
    "${DIRNAME}/build.sh"
fi

mkdir -p "${HOME}/.armlm"

run_args=(--rm)
if [[ "${FVP_RUNTIME}" == container ]]; then
    run_args+=(--progress none)
    if [[ -n "${FVP_CONTAINER_DNS}" ]]; then
        run_args+=(--dns "${FVP_CONTAINER_DNS}")
    fi
fi

"${FVP_RUNTIME}" run "${run_args[@]}" \
  --mount "type=bind,source=${HOME}/.armlm,target=${HOME}/.armlm" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  "fvp:${FVP_VERSION}" /opt/avh-fvp/arm_license_management_utilities/armlm "$@"
