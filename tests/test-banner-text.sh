#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

banner="$(
  env PACKAGE_BANNER_ONLY=true GITHUB_RUN_NUMBER=9 \
    KERNEL_SOURCE=lineageos ROM_FAMILY=los LTO=thin \
    MANAGER=kernelsu-next ENABLE_SUSFS=true \
    manager_build_version_name='v3.2.0' manager_build_version_code=33203 \
    susfs_reported_version=v2.2.0 \
    bash scripts/package-anykernel.sh
)"

echo "${banner}" | grep -q 'Marble Kernel' || { echo "FAIL: missing title" >&2; exit 1; }
echo "${banner}" | grep -q 'Family   : LOS' || { echo "FAIL: family" >&2; exit 1; }
echo "${banner}" | grep -q 'Source   : lineageos' || { echo "FAIL: source" >&2; exit 1; }
echo "${banner}" | grep -q 'SUSFS    : v2.2.0' || { echo "FAIL: susfs" >&2; exit 1; }
echo "${banner}" | grep -q 'LTO      : thin' || { echo "FAIL: lto" >&2; exit 1; }

# Evolution X version must show up on the Source line when provided.
banner_evo="$(
  env PACKAGE_BANNER_ONLY=true GITHUB_RUN_NUMBER=9 \
    KERNEL_SOURCE=evolution-x ROM_FAMILY=los LTO=thin \
    EVOLUTION_X_VERSION=12.4 EVOLUTION_X_ANDROID=17 \
    MANAGER=kernelsu ENABLE_SUSFS=false \
    bash scripts/package-anykernel.sh
)"
echo "${banner_evo}" | grep -q 'Source   : evolution-x · Evolution X 12.4 (Android 17)' || {
  echo "FAIL: Evolution X version missing from banner" >&2
  echo "${banner_evo}" >&2
  exit 1
}
echo "${banner_evo}" | grep -q 'Manager  : kernelsu' || { echo "FAIL: manager line" >&2; exit 1; }

if echo "${banner}" | grep -q '██'; then
  echo "FAIL: ASCII art must not appear in banner" >&2
  exit 1
fi

echo "Banner text tests passed"
