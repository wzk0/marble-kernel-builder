#!/usr/bin/env bash
set -euo pipefail

KERNEL_SOURCE="${KERNEL_SOURCE:-melt}"
# Optional override for branch/tag/commit. Empty means use the preset default
# (or, for presets with version_map, the pinned commit of EVOLUTION_X_VERSION).
SOURCE_REF="${SOURCE_REF:-}"
EVOLUTION_X_VERSION="${EVOLUTION_X_VERSION:-}"

if [[ ! -f config/kernel-sources.json ]]; then
  echo "::error::config/kernel-sources.json is missing"
  exit 1
fi

PYTHON="${PYTHON:-python3}"
if ! resolved_env="$(
  KERNEL_SOURCE="${KERNEL_SOURCE}" SOURCE_REF="${SOURCE_REF}" \
  EVOLUTION_X_VERSION="${EVOLUTION_X_VERSION}" \
  "${PYTHON}" - config/kernel-sources.json <<'PY'
import json
import os
import re
import shlex
import sys

config_path = sys.argv[1]
kernel_source = os.environ.get("KERNEL_SOURCE", "melt")
source_ref_override = os.environ.get("SOURCE_REF", "")
version_request = os.environ.get("EVOLUTION_X_VERSION", "").strip()

with open(config_path, encoding="utf-8") as fh:
    presets = json.load(fh)

if kernel_source not in presets:
    allowed = ", ".join(sorted(presets))
    print(f'::error::Unknown kernel_source preset: {kernel_source}', file=sys.stderr)
    print(f"Allowed: {allowed}", file=sys.stderr)
    sys.exit(1)

preset = presets[kernel_source]
display = preset.get("display") or kernel_source
author = preset.get("author") or display
repo = preset.get("repo") or ""
default_ref = preset.get("default_ref") or ""
rom_label = preset.get("rom_label") or "HyperOS"
rom_family = preset.get("rom_family") or ""
rom_support = preset.get("rom_support") or ""
defconfig_mode = preset.get("defconfig_mode") or ""
defconfig = preset.get("defconfig") or ""
base_defconfig = preset.get("base_defconfig") or ""
fragments = preset.get("config_fragments") or []
recommended_toolchain = preset.get("recommended_toolchain") or ""

# ── Optional ROM-version mapping (config/evolution-x-versions.json) ───────────
# Turns "Evolution X version" into an exact kernel repo/ref/commit/fragment set.
version_id = ""
version_meta = {}
pinned_commit = ""
ref_label = default_ref

if preset.get("version_map"):
    mapping_path = os.path.join(os.path.dirname(config_path), "evolution-x-versions.json")
    if not os.path.exists(mapping_path):
        print(f"::error::{kernel_source} requires version_map but {mapping_path} is missing",
              file=sys.stderr)
        sys.exit(1)
    with open(mapping_path, encoding="utf-8") as fh:
        mapping = json.load(fh)
    versions = mapping.get("versions") or {}
    version_id = version_request or str(mapping.get("default") or "")
    if not version_id:
        print(f"::error::{mapping_path} has no default version and EVOLUTION_X_VERSION is empty",
              file=sys.stderr)
        sys.exit(1)
    version_meta = versions.get(version_id) or {}
    if not version_meta:
        known = ", ".join(sorted(versions)) or "<none>"
        print(f"::error::Unknown version {version_id!r} in {mapping_path}. Known: {known}",
              file=sys.stderr)
        sys.exit(1)

    repo = version_meta.get("kernel_repo") or repo
    ref_label = version_meta.get("kernel_ref") or default_ref
    pinned_commit = version_meta.get("kernel_commit") or ""
    defconfig_mode = version_meta.get("defconfig_mode") or defconfig_mode
    base_defconfig = version_meta.get("base_defconfig") or base_defconfig
    fragments = version_meta.get("config_fragments") or fragments
    recommended_toolchain = (
        version_meta.get("recommended_toolchain")
        or version_meta.get("official_toolchain")
        or recommended_toolchain
    )

    if pinned_commit and not re.fullmatch(r"[0-9a-f]{40}", pinned_commit):
        print(f"::error::kernel_commit for {version_id} must be a full 40-char lowercase hex SHA",
              file=sys.stderr)
        sys.exit(1)
    suffix = version_meta.get("kernel_release_suffix") or ""
    if pinned_commit and suffix and not suffix.endswith(pinned_commit[:12]):
        print(
            f"::error::kernel_release_suffix {suffix!r} does not end with {pinned_commit[:12]!r}; "
            "the pinned commit and the ROM kernel release string disagree (vermagic mismatch)",
            file=sys.stderr,
        )
        sys.exit(1)

config_fragments = " ".join(fragments)

rom_family_norm = (rom_family or "").lower()
if rom_family_norm == "los" or kernel_source in ("lineageos", "evolution-x", "aosp-pablo", "pa-gr"):
    package_family = "LOS"
else:
    package_family = "MELT"

resolved_ref = source_ref_override or pinned_commit or ref_label
if not resolved_ref:
    print(
        f"::error::kernel_source {kernel_source} has no default_ref and SOURCE_REF is empty",
        file=sys.stderr,
    )
    sys.exit(1)

if defconfig_mode == "single":
    if not defconfig:
        print(
            f"::error::kernel_source {kernel_source} uses single defconfig_mode but has no defconfig",
            file=sys.stderr,
        )
        sys.exit(1)
elif defconfig_mode == "gki_fragments":
    if not base_defconfig or not config_fragments:
        print(
            f"::error::kernel_source {kernel_source} uses gki_fragments but base_defconfig/config_fragments are incomplete",
            file=sys.stderr,
        )
        sys.exit(1)
else:
    print(
        f"::error::Unsupported defconfig_mode for {kernel_source}: {defconfig_mode}",
        file=sys.stderr,
    )
    sys.exit(1)

if not repo or "/" not in repo:
    print(f"::error::kernel_source {kernel_source} has invalid repo: {repo}", file=sys.stderr)
    sys.exit(1)

values = {
    "KERNEL_SOURCE": kernel_source,
    "KERNEL_SOURCE_DISPLAY": display,
    "KERNEL_SOURCE_AUTHOR": author,
    "SOURCE_REPO": repo,
    "SOURCE_REF": resolved_ref,
    "SOURCE_REF_LABEL": ref_label,
    "SUPPORTED_ROM_LABEL": rom_label,
    "ROM_FAMILY": rom_family,
    "ROM_SUPPORT": rom_support,
    "DEFCONFIG_MODE": defconfig_mode,
    "DEFCONFIG": defconfig,
    "BASE_DEFCONFIG": base_defconfig,
    "CONFIG_FRAGMENTS": config_fragments,
    "RECOMMENDED_TOOLCHAIN": recommended_toolchain,
    "PACKAGE_FAMILY": package_family,
    "EVOLUTION_X_VERSION": version_id,
    "EVOLUTION_X_ANDROID": version_meta.get("android") or "",
    "EVOLUTION_X_MANIFEST_BRANCH": version_meta.get("manifest_branch") or "",
    "EVOLUTION_X_ROM_BUILD": version_meta.get("rom_build") or "",
    "KERNEL_REF": ref_label,
    "KERNEL_COMMIT": pinned_commit,
    "KERNEL_RELEASE_SUFFIX": version_meta.get("kernel_release_suffix") or "",
    "KERNEL_VERSION_LABEL": version_meta.get("kernel_version") or "",
    "DROIDSPACES_PROFILE": version_meta.get("droidspaces_profile") or "",
    "OFFICIAL_TOOLCHAIN": version_meta.get("official_toolchain") or "",
    "SUSFS_KERNEL_BRANCH_MAPPED": version_meta.get("susfs_kernel_branch") or "",
}
os.makedirs("release", exist_ok=True)
with open("release/kernel-source.env", "w", encoding="utf-8") as fh:
    for k, v in values.items():
        fh.write(f"{k}={shlex.quote(v)}\n")

gh_env = os.environ.get("GITHUB_ENV")
if gh_env and os.path.exists(gh_env):
    with open(gh_env, "a", encoding="utf-8") as fh:
        for k, v in values.items():
            fh.write(f"{k}={v}\n")

gh_out = os.environ.get("GITHUB_OUTPUT")
if gh_out and os.path.exists(gh_out):
    with open(gh_out, "a", encoding="utf-8") as fh:
        for k in ("source_repo", "source_ref", "kernel_source", "kernel_source_display"):
            fh.write(f"{k}={values.get(k.upper(), '')}\n")

for key, value in values.items():
    print(f"{key}={shlex.quote(value)}")
PY
)"; then
  # The resolver already printed an ::error:: line; do not continue with empty vars.
  exit 1
fi
eval "${resolved_env}"

echo "Resolved kernel source preset '${KERNEL_SOURCE}' (${KERNEL_SOURCE_AUTHOR})"
if [[ -n "${EVOLUTION_X_VERSION}" ]]; then
  echo "  evolution_x_version=${EVOLUTION_X_VERSION} (android ${EVOLUTION_X_ANDROID}, manifest ${EVOLUTION_X_MANIFEST_BRANCH})"
  echo "  kernel_commit=${KERNEL_COMMIT}"
  echo "  kernel_release_suffix=${KERNEL_RELEASE_SUFFIX}"
  echo "  droidspaces_profile=${DROIDSPACES_PROFILE}"
fi
echo "  repo=${SOURCE_REPO}"
echo "  ref=${SOURCE_REF}${SOURCE_REF_LABEL:+ (label ${SOURCE_REF_LABEL})}"
echo "  rom_label=${SUPPORTED_ROM_LABEL}"
echo "  defconfig_mode=${DEFCONFIG_MODE}"
if [[ "${DEFCONFIG_MODE}" == "single" ]]; then
  echo "  defconfig=${DEFCONFIG}"
else
  echo "  base_defconfig=${BASE_DEFCONFIG}"
  echo "  fragments=${CONFIG_FRAGMENTS}"
fi
if [[ -n "${RECOMMENDED_TOOLCHAIN}" ]]; then
  echo "  recommended_toolchain=${RECOMMENDED_TOOLCHAIN}"
  if [[ -n "${TOOLCHAIN:-}" && "${TOOLCHAIN}" != "auto" && "${TOOLCHAIN}" != "${RECOMMENDED_TOOLCHAIN}" ]]; then
    echo "::warning::kernel_source '${KERNEL_SOURCE}' recommends toolchain '${RECOMMENDED_TOOLCHAIN}' (selected: ${TOOLCHAIN}). Older Android clang may fail on armv9 flags."
  fi
fi