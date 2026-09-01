#!/usr/bin/env bash

DIRNAME="$(dirname "$(realpath "$0")")"

source "${DIRNAME}/fvprc"

if ! docker image inspect "fvp:${FVP_VERSION}" >/dev/null 2>&1; then
    "${DIRNAME}/build.sh"
fi

if [ ! -d ~/.armlm ]; then
    mkdir -p ~/.armlm
fi

echo -e "Using armlm from FVPs-on-Mac to manage Arm licenses.\n"

docker run --rm \
  --mount "type=bind,src=${HOME}/.armlm/,dst=${HOME}/.armlm/" \
  --env "ARMLM_CACHED_LICENSES_LOCATION=${HOME}/.armlm" \
  "fvp:${FVP_VERSION}" /opt/avh-fvp/arm_license_management_utilities/armlm "$@" 

exit $?
