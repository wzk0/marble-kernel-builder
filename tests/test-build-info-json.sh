#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

PYTHON="${PYTHON:-python3}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

release_dir="${tmp_dir}/release"
mkdir -p "${release_dir}"
cat > "${release_dir}/build-info.txt" <<'INFO'
source_repo=mohdakil2426/android_kernel_xiaomi_marble
source_ref=melt-rebase
source_commit=3673961d444b5e2b879be97a161241243d543bd2
manager=resukisu
manager_repo=ReSukiSU/ReSukiSU
manager_ref=main
manager_commit=88e7f51c3840436b982276ec35bf2876cfec2713
manager_build_version_code=34990
manager_build_version_name=v4.1.0-88e7f51c@ReSukiSU
manager_supported_line=MKSU,RKSU,KOWSU,SukiSU-Ultra,ReSukiSU
enable_susfs=true
susfs_reported_version=v2.2.0
INFO
cat > "${release_dir}/zip-name.env" <<'ENV'
zip_name=AK3_marble_MELT_melt_resukisu-v4.1.0-code34990_susfs-v2.2.0_r7.zip
zip_sha256=abc123
ENV

KERNEL_DIR="${tmp_dir}" bash scripts/write-build-info-json.sh >/dev/null

json_file="${release_dir}/build-info.json"
[[ -f "${json_file}" ]] || {
  echo "FAIL: build-info.json was not created" >&2
  exit 1
}

"${PYTHON}" - "${json_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

assert data["source"]["repo"] == "mohdakil2426/android_kernel_xiaomi_marble"
assert data["manager"]["name"] == "resukisu"
assert data["manager"]["build"]["version_code"] == "34990"
assert data["manager"]["build"]["version_name"] == "v4.1.0-88e7f51c@ReSukiSU"
assert data["manager"]["build"]["supported"] == [
    "MKSU",
    "RKSU",
    "KOWSU",
    "SukiSU-Ultra",
    "ReSukiSU",
]
assert data["susfs"]["enabled"] is True
assert data["susfs"]["reported_version"] == "v2.2.0"
assert data["artifact"]["zip_name"].startswith("AK3_marble_MELT_melt_resukisu")
assert data["artifact"]["zip_sha256"] == "abc123"

# Provenance blocks exist even when the fields are absent (Melt build).
assert data["rom"]["evolution_x_version"] == ""
assert data["kernel"]["commit"] == ""
assert data["droidspaces"]["enabled"] is False
PY

# ── Evolution X / Droidspaces provenance is recorded when present ────────────
cat >> "${release_dir}/build-info.txt" <<'INFO'
kernel_ref=cnb
kernel_commit=658b84f13496fa94659905e5f29b31cfde41d0ce
kernel_release_suffix=-gki-g658b84f13496
kernel_version_label=5.10.269
source_ref_label=cnb
evolution_x_version=12.4
evolution_x_android=17
evolution_x_manifest_branch=cnb
evolution_x_rom_build=EvolutionX-17.0-20261112-marble-12.4-Official
droidspaces_enabled=true
droidspaces_profile=gki-5.10
droidspaces_patch_dir=patches/kernel-sources/evolution-x/droidspaces
official_toolchain=aosp-clang-r563880c
INFO

KERNEL_DIR="${tmp_dir}" bash scripts/write-build-info-json.sh >/dev/null

"${PYTHON}" - "${json_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

assert data["rom"]["evolution_x_version"] == "12.4"
assert data["rom"]["android"] == "17"
assert data["rom"]["manifest_branch"] == "cnb"
assert data["rom"]["build"] == "EvolutionX-17.0-20261112-marble-12.4-Official"
assert data["kernel"]["ref"] == "cnb"
assert data["kernel"]["commit"] == "658b84f13496fa94659905e5f29b31cfde41d0ce"
assert data["kernel"]["release_suffix"] == "-gki-g658b84f13496"
assert data["kernel"]["version"] == "5.10.269"
assert data["kernel"]["official_toolchain"] == "aosp-clang-r563880c"
assert data["droidspaces"]["enabled"] is True
assert data["droidspaces"]["profile"] == "gki-5.10"
assert data["droidspaces"]["patch_dir"].endswith("evolution-x/droidspaces")
PY

echo "Build-info JSON tests passed"