#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run inside a scratch copy so resolve-kernel-source.sh cannot leave a
# release/kernel-source.env behind in the repository (test isolation).
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
mkdir -p "${tmp_dir}/config" "${tmp_dir}/scripts"
cp "${repo_root}/config/kernel-sources.json" "${tmp_dir}/config/"
if [[ -f "${repo_root}/config/evolution-x-versions.json" ]]; then
  cp "${repo_root}/config/evolution-x-versions.json" "${tmp_dir}/config/"
fi
cp "${repo_root}/scripts/resolve-kernel-source.sh" "${repo_root}/scripts/resolve-toolchain.sh" "${tmp_dir}/scripts/"

run() {
  ( cd "${tmp_dir}" && env -u TOOLCHAIN "$@" bash scripts/resolve-toolchain.sh )
}

out="$(run KERNEL_SOURCE=lineageos SOURCE_REF='' TOOLCHAIN=auto)"
echo "${out}" | grep -q 'TOOLCHAIN=llvm-22.1.8' || {
  echo "FAIL: LOS auto should resolve to llvm-22.1.8 (got: ${out})" >&2
  exit 1
}

out="$(run KERNEL_SOURCE=melt SOURCE_REF='' TOOLCHAIN=auto)"
echo "${out}" | grep -Eq 'TOOLCHAIN=android-r416183b' || {
  echo "FAIL: melt auto should resolve to android-r416183b (got: ${out})" >&2
  exit 1
}

out="$(run KERNEL_SOURCE=lineageos SOURCE_REF='' TOOLCHAIN=android-r416183b)"
echo "${out}" | grep -q 'TOOLCHAIN=android-r416183b' || {
  echo "FAIL: explicit override should stick (got: ${out})" >&2
  exit 1
}

echo "Toolchain auto tests passed"
