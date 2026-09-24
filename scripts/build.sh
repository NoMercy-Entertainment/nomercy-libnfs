#!/usr/bin/env bash
# build.sh — Build libnfs for one or all platforms and extract the native binary.
#
# Usage:
#   bash server/network/nomercy-libnfs/scripts/build.sh [platform]
#
# Platforms: win-x64 | linux-x64 | linux-arm64 | osx-x64 | osx-arm64 | all
# Default: all
#
# macOS builds require --build-arg SDK_TARBALL_URL=<url> unless the SDK tarball
# is already staged. See libnfs-darwin-*.dockerfile for details.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PKG_DIR}/output"

PLATFORM="${1:-all}"

# Map RID → dockerfile + output filename
declare -A DOCKERFILE=(
    [win-x64]="libnfs-windows-x86_64.dockerfile"
    [linux-x64]="libnfs-linux-x86_64.dockerfile"
    [linux-arm64]="libnfs-linux-aarch64.dockerfile"
    [osx-x64]="libnfs-darwin-x86_64.dockerfile"
    [osx-arm64]="libnfs-darwin-arm64.dockerfile"
)

declare -A BINARY=(
    [win-x64]="libnfs.dll"
    [linux-x64]="libnfs.so"
    [linux-arm64]="libnfs.so"
    [osx-x64]="libnfs.dylib"
    [osx-arm64]="libnfs.dylib"
)

# Export stage names that produce the final scratch image
declare -A EXPORT_TARGET=(
    [win-x64]="export-win-x64"
    [linux-x64]="export-linux-x64"
    [linux-arm64]="export-linux-arm64"
    [osx-x64]="export-osx-x64"
    [osx-arm64]="export-osx-arm64"
)

build_platform() {
    local rid="$1"
    local dockerfile="${DOCKERFILE[$rid]}"
    local binary="${BINARY[$rid]}"
    local target="${EXPORT_TARGET[$rid]}"
    local out_dir="${OUTPUT_DIR}/${rid}"
    local out_file="${out_dir}/${binary}"

    echo "------------------------------------------------------------"
    echo "Building: ${rid}"
    echo "  Dockerfile : ${dockerfile}"
    echo "  Output     : ${out_file}"
    echo "------------------------------------------------------------"

    mkdir -p "${out_dir}"

    # Build base first (cached on subsequent runs)
    docker build \
        --no-cache=false \
        -f "${PKG_DIR}/libnfs-base.dockerfile" \
        -t libnfs-base \
        "${PKG_DIR}"

    # Build platform image up to the export stage
    docker build \
        --no-cache=false \
        --build-context libnfs-base=docker-image://libnfs-base \
        -f "${PKG_DIR}/${dockerfile}" \
        --target "${target}" \
        -t "libnfs-${rid}" \
        "${PKG_DIR}"

    # Extract binary from the scratch image. `docker create` rejects scratch
    # images with no entrypoint, so pass `--entrypoint /bin/true` (the binary
    # never actually runs — we just need a container to cp from).
    CONTAINER_ID=$(docker create --entrypoint /bin/true "libnfs-${rid}" 2>/dev/null \
                   || docker create "libnfs-${rid}" sh)
    docker cp "${CONTAINER_ID}:/${binary}" "${out_file}"
    docker rm "${CONTAINER_ID}" >/dev/null

    local size
    size=$(du -sh "${out_file}" | cut -f1)
    echo "Extracted ${out_file} (${size})"

    # Sanity: reject obviously-wrong tiny files
    local bytes
    bytes=$(wc -c < "${out_file}")
    if [ "${bytes}" -lt 204800 ]; then
        echo "ERROR: ${binary} is only ${bytes} bytes — expected >= 200KB. Build may have failed." >&2
        exit 1
    fi

    echo "OK: ${rid}"
}

if [ "${PLATFORM}" = "all" ]; then
    for rid in win-x64 linux-x64 linux-arm64 osx-x64 osx-arm64; do
        build_platform "${rid}"
    done
else
    if [ -z "${DOCKERFILE[$PLATFORM]+set}" ]; then
        echo "Unknown platform: ${PLATFORM}" >&2
        echo "Valid: win-x64 linux-x64 linux-arm64 osx-x64 osx-arm64 all" >&2
        exit 1
    fi
    build_platform "${PLATFORM}"
fi

# Regenerate checksums
echo "Updating ${OUTPUT_DIR}/CHECKSUMS.txt"
(
    cd "${OUTPUT_DIR}"
    find . -type f -name "libnfs.*" | sort | xargs sha256sum > CHECKSUMS.txt
    cat CHECKSUMS.txt
)

echo ""
echo "Done. Binaries in ${OUTPUT_DIR}/"
