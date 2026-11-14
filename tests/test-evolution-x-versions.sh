#!/usr/bin/env bash
# Schema + resolution tests for config/evolution-x-versions.json.
# No network, no kernel tree.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

PYTHON="${PYTHON:-python3}"
mapping=config/evolution-x-versions.json
presets=config/kernel-sources.json

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "${mapping}" ]] || fail "config/evolution-x-versions.json is missing"

# ── Schema ───────────────────────────────────────────────────────────────────
"${PYTHON}" - "${mapping}" "${presets}" <<'PY'
import json
import re
import sys

mapping = json.load(open(sys.argv[1], encoding="utf-8"))
presets = json.load(open(sys.argv[2], encoding="utf-8"))

versions = mapping.get("versions")
assert isinstance(versions, dict) and versions, "versions must be a non-empty object"
default = mapping.get("default")
assert default in versions, f"default {default!r} must exist in versions"

required = {
    "android", "manifest_branch", "kernel_repo", "kernel_ref", "kernel_commit",
    "kernel_version", "kernel_release_suffix", "defconfig_mode",
    "base_defconfig", "config_fragments", "droidspaces_profile", "status",
}

for name, meta in versions.items():
    assert re.fullmatch(r"\d+\.\d+(\.\d+)?", name), f"version key {name!r} must look like 12.4"
    missing = required - set(meta)
    assert not missing, f"{name}: missing fields {sorted(missing)}"

    assert re.fullmatch(r"[0-9a-f]{40}", meta["kernel_commit"]), \
        f"{name}: kernel_commit must be a full 40-char lowercase hex sha"

    suffix = meta["kernel_release_suffix"]
    assert suffix.endswith(meta["kernel_commit"][:12]), (
        f"{name}: kernel_release_suffix {suffix!r} must end with "
        f"{meta['kernel_commit'][:12]!r} (vermagic guard)"
    )
    assert meta["droidspaces_profile"].startswith("gki-"), f"{name}: droidspaces_profile"
    assert meta["defconfig_mode"] in ("gki_fragments", "single"), f"{name}: defconfig_mode"
    assert isinstance(meta["config_fragments"], list) and meta["config_fragments"], \
        f"{name}: config_fragments must be a non-empty list"

    preset_id = meta.get("kernel_source_preset", "evolution-x")
    assert preset_id in presets, f"{name}: kernel_source_preset {preset_id!r} not in presets"
    assert presets[preset_id].get("version_map") is True, \
        f"{name}: preset {preset_id!r} must set version_map=true"

print("schema ok")
PY

# ── Resolution through resolve-kernel-source.sh ──────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/config" "${tmp}/scripts"
cp "${mapping}" "${presets}" "${tmp}/config/"
cp scripts/resolve-kernel-source.sh "${tmp}/scripts/"

resolve() {
  ( cd "${tmp}" && env -u SOURCE_REF "$@" bash scripts/resolve-kernel-source.sh >/dev/null 2>&1 )
}

env_file() {
  cat "${tmp}/release/kernel-source.env"
}

default_commit="$("${PYTHON}" -c "import json;print(json.load(open('${mapping}'))['versions']['12.4']['kernel_commit'])")"

# No version requested -> mapping default applies and the checkout is pinned by commit.
resolve KERNEL_SOURCE=evolution-x EVOLUTION_X_VERSION='' || fail "resolver failed for default version"
out="$(env_file)"
grep -q "^SOURCE_REF=${default_commit}\$" <<<"${out}" || fail "default version must pin SOURCE_REF to the commit (got: $(grep '^SOURCE_REF=' <<<"${out}"))"
grep -q '^SOURCE_REF_LABEL=cnb$' <<<"${out}" || fail "SOURCE_REF_LABEL must keep the human branch"
grep -q '^KERNEL_COMMIT=658b84f13496fa94659905e5f29b31cfde41d0ce$' <<<"${out}" || fail "KERNEL_COMMIT missing"
grep -q '^EVOLUTION_X_VERSION=12.4$' <<<"${out}" || fail "EVOLUTION_X_VERSION missing"
grep -q '^EVOLUTION_X_ANDROID=17$' <<<"${out}" || fail "EVOLUTION_X_ANDROID missing"
grep -q '^DROIDSPACES_PROFILE=gki-5.10$' <<<"${out}" || fail "DROIDSPACES_PROFILE missing"
grep -q '^SUSFS_KERNEL_BRANCH_MAPPED=gki-android12-5.10$' <<<"${out}" || fail "SUSFS branch mapping missing"
grep -q 'vendor/waipio_GKI.config' <<<"${out}" || fail "fragments must come from the mapping"
grep -q '^DEFCONFIG_MODE=gki_fragments$' <<<"${out}" || fail "defconfig mode"

# Explicit version behaves the same.
resolve KERNEL_SOURCE=evolution-x EVOLUTION_X_VERSION=12.4 || fail "resolver failed for 12.4"
grep -q "^SOURCE_REF=${default_commit}\$" < <(env_file) || fail "explicit version must pin the commit"

# Unknown version must fail loudly.
if resolve KERNEL_SOURCE=evolution-x EVOLUTION_X_VERSION=9.9; then
  fail "unknown version must be rejected"
fi

# Explicit source_ref override still wins over the pin.
resolve KERNEL_SOURCE=evolution-x EVOLUTION_X_VERSION=12.4 SOURCE_REF=cnb || fail "override run failed"
grep -q '^SOURCE_REF=cnb$' < <(env_file) || fail "SOURCE_REF override must win over the pin"

# Vermagic guard: a suffix that disagrees with the pinned commit must be rejected.
"${PYTHON}" - "${mapping}" "${tmp}/config/evolution-x-versions.json" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
data["versions"]["12.4"]["kernel_release_suffix"] = "-gki-gdeadbeefcafe"
json.dump(data, open(sys.argv[2], "w", encoding="utf-8"), indent=2)
PY
if resolve KERNEL_SOURCE=evolution-x EVOLUTION_X_VERSION=12.4; then
  fail "release-suffix/commit mismatch must be rejected (vermagic guard)"
fi

echo "Evolution X version mapping tests passed"