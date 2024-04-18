#!/usr/bin/env bash

EXITCODE=0

source "$(dirname "$0")/fvprc"

if ! which -s docker; then
    echo "docker is missing on your system"
    EXITCODE=1
fi

if ! docker info >/dev/null; then
    echo "docker daemon not responding"
    EXITCODE=1
fi

if [ $EXITCODE -gt 0 ]; then
    echo "Some requirements are missing!"
    exit $EXITCODE
fi

if [ ! -d ~/.armlm ]; then
    echo "No Arm license cache found at ~/.armlm"
    echo "Activate Arm user based license."
    echo "The community license can be activates with:"
    echo "armlm --server https://mdk-preview.keil.arm.com --product KEMDK-COM0"
fi 

pushd "$(dirname "$0")" || exit

docker build -t "fvp:${FVP_VERSION}" \
    --build-arg FVP_VERSION="${FVP_VERSION}" \
    --build-arg FVP_BASE_URL="${FVP_BASE_URL}" \
    --build-arg FVP_ARCHIVE="${FVP_ARCHIVE}" \
    --build-arg USERNAME="$(whoami)" \
    --build-arg USERID="$(id -u)" \
    "$@" . || exit

mkdir -p bin
while IFS= read -r -d '' model; do
    model="$(basename "${model}")"
    if [ ! -L "bin/${model}" ]; then
        ln -s ../fvp.sh "bin/${model}"
    fi
done < <(docker run "fvp:${FVP_VERSION}" find /opt/avh-fvp/bin/ -maxdepth 1 -type f -executable -follow -print0)

exit 0
