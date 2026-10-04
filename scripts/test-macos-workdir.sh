#!/usr/bin/env bash
# Regression test for the macOS "Fetch + verify libnfs source" step in
# .github/workflows/build.yml (issues #2 and #4).
#
# The step must:
#   1. work in a per-job folder under RUNNER_TEMP, never a fixed shared path;
#   2. be safe to run twice on the same runner: the second run must not move
#      the fresh tree inside the old one (mv onto an existing directory).
#
# Runs on any box with bash + python3 (PyYAML). Network is stubbed: a fake
# `curl` writes a small fixture tarball, and LIBNFS_SHA256 is its real hash,
# so the step's own shasum check still runs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/build.yml"
STEP_NAME="Fetch + verify libnfs source"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT

# --- extract the step's run block from the workflow -------------------------
python3 - "${WORKFLOW}" "${STEP_NAME}" > "${SANDBOX}/step.sh" <<'PY'
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for step in wf["jobs"]["macos-build"]["steps"]:
    if step.get("name") == sys.argv[2]:
        print(step["run"]); break
else:
    sys.exit("step not found: " + sys.argv[2])
PY

# --- fixture: a tarball shaped like the upstream release archive ------------
export LIBNFS_TAG="libnfs-6.0.2"
export RID="osx-test"
mkdir -p "${SANDBOX}/fixture/libnfs-${LIBNFS_TAG}"
echo marker > "${SANDBOX}/fixture/libnfs-${LIBNFS_TAG}/marker"
tar -C "${SANDBOX}/fixture" -czf "${SANDBOX}/fixture.tar.gz" "libnfs-${LIBNFS_TAG}"
LIBNFS_SHA256="$(shasum -a 256 "${SANDBOX}/fixture.tar.gz" | cut -d' ' -f1)"
export LIBNFS_SHA256

# fake curl: writes the fixture to the -o target
mkdir -p "${SANDBOX}/bin"
cat > "${SANDBOX}/bin/curl" <<EOF
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  case "\$1" in -o) cp "${SANDBOX}/fixture.tar.gz" "\$2"; exit 0;; esac
  shift
done
exit 1
EOF
chmod +x "${SANDBOX}/bin/curl"

export RUNNER_TEMP="${SANDBOX}/runner-temp"
export GITHUB_ENV="${SANDBOX}/github.env"
mkdir -p "${RUNNER_TEMP}"
: > "${GITHUB_ENV}"

run_step() {
  PATH="${SANDBOX}/bin:${PATH}" bash "${SANDBOX}/step.sh"
}

WORK="${RUNNER_TEMP}/libnfs-${RID}"
FAIL=0

echo "== run 1 =="
run_step
if [ -f "${WORK}/libnfs/marker" ]; then
  echo "ok: tree is in the per-job folder ${WORK}"
else
  echo "FAIL: libnfs tree is not under the per-job folder ${WORK}"
  echo "      (the step uses a fixed shared path; see where it went:)"
  find /tmp/libnfs-build "${RUNNER_TEMP}" -maxdepth 3 -name marker 2>/dev/null | sed 's/^/      /'
  FAIL=1
fi

echo "== run 2 (same runner, same job) =="
run_step
for root in "${WORK}" /tmp/libnfs-build; do
  if [ -d "${root}/libnfs/libnfs-${LIBNFS_TAG}" ]; then
    echo "FAIL: second run nested the fresh tree inside the old one: ${root}/libnfs/libnfs-${LIBNFS_TAG}"
    FAIL=1
  fi
done
if [ -f "${WORK}/libnfs/marker" ] && [ ! -d "${WORK}/libnfs/libnfs-${LIBNFS_TAG}" ]; then
  echo "ok: second run starts from a clean folder"
fi

if [ "${FAIL}" -ne 0 ]; then
  echo "test-macos-workdir: FAILED"
  exit 1
fi
echo "test-macos-workdir: PASSED (2 checks)"
