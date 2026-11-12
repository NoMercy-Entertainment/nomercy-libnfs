#!/usr/bin/env bash
# verify.sh — Verify libnfs binaries: checksums + basic symbol sanity.
#
# Usage: bash server/network/nomercy-libnfs/scripts/verify.sh [platform]
# Default: verify all platforms present in output/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PKG_DIR}/output"

PLATFORM="${1:-all}"

# ── Source tarball SHA256 ─────────────────────────────────────
# libnfs-base.dockerfile is the one source of the tag and its archive hash (libnfs#5); the
# build enforces it there. To bump: change both values in the dockerfile and in build.yml, from
#   curl -sSL https://github.com/sahlberg/libnfs/archive/refs/tags/<tag>.tar.gz | sha256sum
# scripts/check-source-hash.sh fails when the files disagree.
dockerfile_env() { grep -m1 -oE "^ENV $1=[A-Za-z0-9._-]+" "${PKG_DIR}/libnfs-base.dockerfile" | cut -d= -f2; }
LIBNFS_TAG="$(dockerfile_env LIBNFS_TAG)"
KNOWN_SOURCE_SHA256="$(dockerfile_env LIBNFS_SHA256)"

if [ "${PLATFORM}" = "--print-source-sha" ]; then
    echo "${LIBNFS_TAG} ${KNOWN_SOURCE_SHA256}"
    exit 0
fi

# ── Required exports in each binary ──────────────────────────
REQUIRED_SYMBOLS=(
    nfs_init_context
    nfs_destroy_context
    nfs_mount
    nfs_opendir
    mount_getexports
    mount_free_export_list
)

PASS=0
FAIL=0

verify_checksums() {
    echo "Verifying checksums against ${OUTPUT_DIR}/CHECKSUMS.txt"
    if [ ! -f "${OUTPUT_DIR}/CHECKSUMS.txt" ]; then
        echo "WARN: CHECKSUMS.txt not found — run build.sh first"
        return
    fi
    (cd "${OUTPUT_DIR}" && sha256sum -c CHECKSUMS.txt)
    echo "Checksums OK"
}

verify_symbols_linux() {
    local file="$1"
    echo "Checking symbols in ${file}"
    for sym in "${REQUIRED_SYMBOLS[@]}"; do
        if nm -D "${file}" 2>/dev/null | grep " ${sym}$" > /dev/null; then
            echo "  OK: ${sym}"
        else
            echo "  MISSING: ${sym}" >&2
            FAIL=$((FAIL + 1))
        fi
    done
}

verify_symbols_windows() {
    local file="$1"
    echo "Checking exports in ${file}"
    local tool=""
    # Prefer cross-objdump if available (CI), fall back to host objdump
    for candidate in x86_64-w64-mingw32-objdump objdump; do
        if command -v "${candidate}" >/dev/null 2>&1; then
            tool="${candidate}"
            break
        fi
    done
    if [ -z "${tool}" ]; then
        echo "  SKIP: no objdump available for .dll inspection"
        return
    fi
    for sym in "${REQUIRED_SYMBOLS[@]}"; do
        if "${tool}" -p "${file}" 2>/dev/null | grep "${sym}" > /dev/null; then
            echo "  OK: ${sym}"
        else
            echo "  MISSING: ${sym}" >&2
            FAIL=$((FAIL + 1))
        fi
    done
}

verify_platform() {
    local rid="$1"
    local dir="${OUTPUT_DIR}/${rid}"

    echo ""
    echo "=== ${rid} ==="

    case "${rid}" in
        win-x64)
            local f="${dir}/libnfs.dll"
            [ -f "${f}" ] || { echo "NOT BUILT: ${f}"; return; }
            echo "Size: $(du -sh "${f}" | cut -f1)"
            verify_symbols_windows "${f}"
            ;;
        linux-x64|linux-arm64)
            local f="${dir}/libnfs.so"
            [ -f "${f}" ] || { echo "NOT BUILT: ${f}"; return; }
            echo "Size: $(du -sh "${f}" | cut -f1)"
            if command -v nm >/dev/null 2>&1; then
                verify_symbols_linux "${f}"
            else
                echo "  SKIP: nm not available"
            fi
            ;;
        osx-x64|osx-arm64)
            local f="${dir}/libnfs.dylib"
            [ -f "${f}" ] || { echo "NOT BUILT: ${f}"; return; }
            echo "Size: $(du -sh "${f}" | cut -f1)"
            if command -v nm >/dev/null 2>&1; then
                for sym in "${REQUIRED_SYMBOLS[@]}"; do
                    if nm -gU "${f}" 2>/dev/null | grep "${sym}" > /dev/null; then
                        echo "  OK: ${sym}"
                    else
                        echo "  MISSING: ${sym}" >&2
                        FAIL=$((FAIL + 1))
                    fi
                done
            else
                echo "  SKIP: nm not available"
            fi
            ;;
    esac
    PASS=$((PASS + 1))
}

verify_checksums

if [ "${PLATFORM}" = "all" ]; then
    for rid in win-x64 linux-x64 linux-arm64 osx-x64 osx-arm64; do
        verify_platform "${rid}"
    done
else
    verify_platform "${PLATFORM}"
fi

echo ""
echo "Source SHA256 for ${LIBNFS_TAG}: ${KNOWN_SOURCE_SHA256}"
echo ""
echo "Results: ${PASS} platforms inspected, ${FAIL} symbol failures"
[ "${FAIL}" -eq 0 ] || exit 1
