#!/usr/bin/env bash
# verify.sh — Verify libnfs binaries: checksums + basic symbol sanity.
#
# Usage: bash packages/nomercy-libnfs/scripts/verify.sh [platform]
# Default: verify all platforms present in output/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${PKG_DIR}/output"

PLATFORM="${1:-all}"

# ── Source tarball SHA256 ─────────────────────────────────────
# libnfs-6.0.2 tag archive from GitHub:
# https://github.com/sahlberg/libnfs/archive/refs/tags/libnfs-6.0.2.tar.gz
#
# Verify / regenerate before first build:
#   wget -qO- https://github.com/sahlberg/libnfs/archive/refs/tags/libnfs-6.0.2.tar.gz | sha256sum
# Update this value and LIBNFS_SHA256 in libnfs-base.dockerfile if it differs.
KNOWN_SOURCE_SHA256="8e03a30c5b11a4aebcc69af5b85d9ecc28fa0a4cdd38b76ec50cde38b6d53d45"

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
        if nm -D "${file}" 2>/dev/null | grep -q " ${sym}$"; then
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
        if "${tool}" -p "${file}" 2>/dev/null | grep -q "${sym}"; then
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
                    if nm -gU "${f}" 2>/dev/null | grep -q "${sym}"; then
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
echo "Source SHA256 for libnfs-6.0.2: ${KNOWN_SOURCE_SHA256}"
echo ""
echo "Results: ${PASS} platforms inspected, ${FAIL} symbol failures"
[ "${FAIL}" -eq 0 ] || exit 1
