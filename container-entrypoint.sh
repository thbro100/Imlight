#!/usr/bin/env bash
set -euo pipefail

DATA_DIR="${IMLIGHT_DATA_DIR:-/data}"
TYPE_INPUT_DIR="${IMLIGHT_TYPE_INPUT_DIR:-${DATA_DIR}/imcodec-inputs/types}"
MESSAGE_INPUT_DIR="${IMLIGHT_MESSAGE_INPUT_DIR:-${DATA_DIR}/imcodec-inputs/messages}"
CONFIG_DIR="${IMLIGHT_CONFIG_DIR:-${DATA_DIR}/config}"
BUILD_CACHE_DIR="${IMLIGHT_BUILD_CACHE_DIR:-${DATA_DIR}/build-cache}"
SOURCE_REPOSITORY="${IMLIGHT_SOURCE_REPOSITORY:?IMLIGHT_SOURCE_REPOSITORY must be set}"
SOURCE_REVISION="${IMLIGHT_SOURCE_REVISION:?IMLIGHT_SOURCE_REVISION must be set}"
PUBLISH_DIR="${BUILD_CACHE_DIR}/publish"
BUILD_KEY_FILE="${BUILD_CACHE_DIR}/build-key"

if [[ ! -d "${TYPE_INPUT_DIR}" ]] || ! find "${TYPE_INPUT_DIR}" -maxdepth 1 -type f -name '*.json' -print -quit | grep -q .; then
    echo "No Imcodec type JSON found in ${TYPE_INPUT_DIR}. Mount user-provided generator inputs there." >&2
    exit 1
fi

if [[ ! -d "${MESSAGE_INPUT_DIR}" ]] || ! find "${MESSAGE_INPUT_DIR}" -maxdepth 1 -type f -name '*Messages*.xml' -print -quit | grep -q .; then
    echo "No Imcodec message XML found in ${MESSAGE_INPUT_DIR}. Mount user-provided generator inputs there." >&2
    exit 1
fi

if [[ ! -f "${CONFIG_DIR}/Imlight.ini" ]] || [[ ! -f "${CONFIG_DIR}/akka.conf" ]]; then
    echo "Mount customized Imlight.ini and akka.conf in ${CONFIG_DIR} before starting the server." >&2
    exit 1
fi

mkdir -p "${DATA_DIR}/app/logs" \
    "${DATA_DIR}/app/spiraldb-cache" "${DATA_DIR}/ImlightEmbeddedDatabase" \
    "${DATA_DIR}/home" "${BUILD_CACHE_DIR}"

INPUT_HASH="$({
    find "${TYPE_INPUT_DIR}" -maxdepth 1 -type f -name '*.json' -print0
    find "${MESSAGE_INPUT_DIR}" -maxdepth 1 -type f -name '*Messages*.xml' -print0
} | sort -z | xargs -0 -r sha256sum | sha256sum | cut -d ' ' -f 1)"
BUILD_KEY="${SOURCE_REPOSITORY}-${SOURCE_REVISION}-${INPUT_HASH}"

if [[ ! -f "${BUILD_KEY_FILE}" ]] || [[ "$(cat "${BUILD_KEY_FILE}")" != "${BUILD_KEY}" ]] || [[ ! -f "${PUBLISH_DIR}/Imlight.Director.dll" ]]; then
    echo "Preparing Imlight ${SOURCE_REVISION} using the mounted Imcodec inputs..."
    TEMP_DIR="$(mktemp -d /tmp/imlight-build.XXXXXX)"
    trap 'rm -rf "${TEMP_DIR}"' EXIT
    SOURCE_DIR="${TEMP_DIR}/source"
    TEMP_PUBLISH_DIR="${TEMP_DIR}/publish"

    mkdir -p "${SOURCE_DIR}"
    git -C "${SOURCE_DIR}" init --quiet
    git -C "${SOURCE_DIR}" remote add origin "${SOURCE_REPOSITORY}"
    git -C "${SOURCE_DIR}" fetch --quiet --depth=1 origin "${SOURCE_REVISION}"
    git -C "${SOURCE_DIR}" checkout --quiet --detach FETCH_HEAD
    git -C "${SOURCE_DIR}" submodule update --init --recursive --depth 1

    OBJECT_PROPERTY_INPUTS="${SOURCE_DIR}/submodule/Imcodec/src/Imcodec.ObjectProperty/GeneratorInput"
    MESSAGE_LAYER_INPUTS="${SOURCE_DIR}/submodule/Imcodec/src/Imcodec.MessageLayer/GeneratorInput"
    mkdir -p "${OBJECT_PROPERTY_INPUTS}" "${MESSAGE_LAYER_INPUTS}"
    cp -a "${TYPE_INPUT_DIR}/." "${OBJECT_PROPERTY_INPUTS}/"
    cp -a "${MESSAGE_INPUT_DIR}/." "${MESSAGE_LAYER_INPUTS}/"

    dotnet publish "${SOURCE_DIR}/src/Imlight.Director/Imlight.Director.csproj" \
        --configuration Release \
        --output "${TEMP_PUBLISH_DIR}"

    test -f "${TEMP_PUBLISH_DIR}/Imlight.Director.dll"
    rm -rf "${PUBLISH_DIR}"
    mkdir -p "${PUBLISH_DIR}"
    cp -a "${TEMP_PUBLISH_DIR}/." "${PUBLISH_DIR}/"
    rm -rf "${TEMP_DIR}"
    trap - EXIT
    printf '%s' "${BUILD_KEY}" > "${BUILD_KEY_FILE}"
    echo "Imlight runtime build cached at ${PUBLISH_DIR}."
else
    echo "Using cached Imlight runtime build for ${SOURCE_REVISION}."
fi

if [[ -f "${CONFIG_DIR}/Imlight.ini" ]]; then
    cp "${CONFIG_DIR}/Imlight.ini" "${PUBLISH_DIR}/Config/Imlight.ini"
fi
if [[ -f "${CONFIG_DIR}/akka.conf" ]]; then
    cp "${CONFIG_DIR}/akka.conf" "${PUBLISH_DIR}/Config/akka.conf"
fi

cd "${DATA_DIR}/app"
exec dotnet "${PUBLISH_DIR}/Imlight.Director.dll"
