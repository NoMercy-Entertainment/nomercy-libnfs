#!/bin/bash
# One libnfs source hash everywhere (libnfs#5). libnfs-base.dockerfile is the source; build.yml
# (the macOS jobs) must pin the same tag and hash, and verify.sh must print that same hash.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

value() { grep -m1 -oE "$2[=:] *[A-Za-z0-9._-]+" "$1" | sed -E "s/^$2[=:] *//"; }
docker_tag=$(value "$DIR/libnfs-base.dockerfile" LIBNFS_TAG)
docker_sha=$(value "$DIR/libnfs-base.dockerfile" LIBNFS_SHA256)
ci_tag=$(value "$DIR/.github/workflows/build.yml" LIBNFS_TAG)
ci_sha=$(value "$DIR/.github/workflows/build.yml" LIBNFS_SHA256)
verify_line=$(bash "$DIR/scripts/verify.sh" --print-source-sha 2>/dev/null || true)

fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want '$3' got '$2')"; fail=1; fi; }
check "the dockerfile pins a 64-hex hash" "$(printf '%s' "$docker_sha" | grep -cE '^[0-9a-f]{64}$')" "1"
check "build.yml pins the same tag" "$ci_tag" "$docker_tag"
check "build.yml pins the same hash" "$ci_sha" "$docker_sha"
check "verify.sh reports the same hash" "$verify_line" "$docker_tag $docker_sha"
exit $fail
