#!/usr/bin/env bash
set -euo pipefail

MATRIX_ARTIFACTS_DIR="${MATRIX_ARTIFACTS_DIR:-matrix-artifacts}"
MATRIX_SUMMARY="${MATRIX_SUMMARY:-matrix-summary.md}"
RELEASE_ASSETS_FILE="${RELEASE_ASSETS_FILE:-release-assets.txt}"
BUILD_SCOPE="${BUILD_SCOPE:-}"
SOURCE_RUN_NUMBER="${SOURCE_RUN_NUMBER:-}"

if [[ ! -d "${MATRIX_ARTIFACTS_DIR}" ]]; then
  echo "::error::Matrix artifacts directory not found: ${MATRIX_ARTIFACTS_DIR}"
  exit 1
fi

artifact_dirs=()
if [[ -f "${MATRIX_ARTIFACTS_DIR}/build-info.txt" && \
      -f "${MATRIX_ARTIFACTS_DIR}/build-info.json" && \
      -f "${MATRIX_ARTIFACTS_DIR}/zip-name.env" ]]; then
  artifact_dirs+=("${MATRIX_ARTIFACTS_DIR}")
fi

mapfile -d '' -t nested_artifact_dirs < <(
  find "${MATRIX_ARTIFACTS_DIR}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z
)
artifact_dirs+=("${nested_artifact_dirs[@]}")
if [[ "${#artifact_dirs[@]}" -eq 0 ]]; then
  echo "::error::No matrix artifacts found in ${MATRIX_ARTIFACTS_DIR}"
  exit 1
fi

declare -A seen_zip_names=()
assets_tmp="$(mktemp)"
trap 'rm -f "${assets_tmp}"' EXIT
detected_scope=""

# Release identity collected from build-info.txt of every verified artifact.
declare -A seen_kernel_source=() seen_rom_version=() seen_droidspaces=()
manager_order=()

for artifact_dir in "${artifact_dirs[@]}"; do
  artifact_name="$(basename "${artifact_dir}")"
  if [[ ! "${artifact_name}" =~ -(image-only|full)-r[0-9]+$ ]]; then
    if [[ "${artifact_dir}" == "${MATRIX_ARTIFACTS_DIR}" && "${BUILD_SCOPE}" =~ ^(image-only|full)$ ]]; then
      artifact_scope="${BUILD_SCOPE}"
    else
      echo "::error::Artifact name does not contain a valid build scope: ${artifact_name}"
      exit 1
    fi
  else
    artifact_scope="${BASH_REMATCH[1]}"
  fi
  if [[ -n "${detected_scope}" && "${artifact_scope}" != "${detected_scope}" ]]; then
    echo "::error::Target run contains mixed build scopes"
    exit 1
  fi
  detected_scope="${artifact_scope}"

  for required_file in build-info.txt build-info.json zip-name.env; do
    if [[ ! -f "${artifact_dir}/${required_file}" ]]; then
      echo "::error::Missing ${required_file} in ${artifact_dir}"
      exit 1
    fi
  done
  if ! python3 -m json.tool "${artifact_dir}/build-info.json" >/dev/null; then
    echo "::error::Invalid build-info.json in ${artifact_dir}"
    exit 1
  fi

  if [[ "$(grep -c '^zip_name=' "${artifact_dir}/zip-name.env")" -ne 1 ]]; then
    echo "::error::Expected one zip_name entry in ${artifact_dir}/zip-name.env"
    exit 1
  fi
  zip_name="$(sed -n 's/^zip_name=//p' "${artifact_dir}/zip-name.env")"
  if [[ ! "${zip_name}" =~ ^[A-Za-z0-9._-]+\.zip$ ]]; then
    echo "::error::Invalid zip_name metadata in ${artifact_dir}"
    exit 1
  fi
  if [[ -n "${seen_zip_names[${zip_name}]:-}" ]]; then
    echo "::error::Duplicate promoted ZIP name: ${zip_name}"
    exit 1
  fi
  seen_zip_names["${zip_name}"]=1

  zip_path="${artifact_dir}/${zip_name}"
  checksum_path="${zip_path}.sha256"
  if [[ ! -f "${zip_path}" || ! -f "${checksum_path}" ]]; then
    echo "::error::Missing ZIP or checksum for ${zip_name}"
    exit 1
  fi

  mapfile -t artifact_zips < <(find "${artifact_dir}" -maxdepth 1 -type f -name '*.zip' -print)
  if [[ "${#artifact_zips[@]}" -ne 1 ]]; then
    echo "::error::Expected exactly one flashable ZIP in ${artifact_dir}"
    exit 1
  fi

  read -r expected_hash expected_name extra < "${checksum_path}" || true
  # Git Bash / binary-mode sha256sum may prefix the filename with '*'.
  expected_name="${expected_name#\*}"
  if [[ ! "${expected_hash:-}" =~ ^[a-fA-F0-9]{64}$ || \
        "${expected_name:-}" != "${zip_name}" || -n "${extra:-}" ]]; then
    echo "::error::Invalid checksum metadata for ${zip_name}"
    exit 1
  fi
  actual_hash="$(sha256sum "${zip_path}" | awk '{print $1}')"
  if [[ "${actual_hash}" != "${expected_hash,,}" ]]; then
    echo "::error::Checksum mismatch for ${zip_name}"
    exit 1
  fi
  info_field() { sed -n "s/^$1=//p" "${artifact_dir}/build-info.txt" | head -n1; }
  src="$(info_field kernel_source)"
  [[ -n "${src}" ]] && seen_kernel_source["${src}"]=1
  rom="$(info_field evolution_x_version)"
  [[ -n "${rom}" ]] && seen_rom_version["${rom}"]=1
  ds="$(info_field droidspaces_enabled)"
  [[ -n "${ds}" ]] && seen_droidspaces["${ds}"]=1
  mgr="$(info_field manager)"
  if [[ -n "${mgr}" ]]; then
    case " ${manager_order[*]-} " in
      *" ${mgr} "*) ;;
      *) manager_order+=("${mgr}") ;;
    esac
  fi

  echo "${zip_name}: OK"
  realpath "${zip_path}" >> "${assets_tmp}"
done

if [[ ! -s "${assets_tmp}" ]]; then
  echo "::error::No verified flashable ZIPs were selected"
  exit 1
fi

MATRIX_ARTIFACTS_DIR="${MATRIX_ARTIFACTS_DIR}" \
MATRIX_SUMMARY="${MATRIX_SUMMARY}" \
BUILD_SCOPE="${BUILD_SCOPE:-${detected_scope}}" \
SOURCE_RUN_NUMBER="${SOURCE_RUN_NUMBER}" \
  bash scripts/generate-matrix-summary.sh >/dev/null

# Release notes: full matrix summary minus CI-only Cache section.
# shellcheck disable=SC1091
source scripts/lib/summary-common.sh
if [[ -z "${RELEASE_NOTES_FILE:-}" ]]; then
  if [[ "${MATRIX_SUMMARY}" == */* ]]; then
    RELEASE_NOTES_FILE="$(dirname "${MATRIX_SUMMARY}")/matrix-summary-release.md"
  else
    RELEASE_NOTES_FILE="matrix-summary-release.md"
  fi
fi
summary_strip_cache_section "${MATRIX_SUMMARY}" "${RELEASE_NOTES_FILE}"
if grep -E 'marble-ci-cache|^## .*Cache$' "${RELEASE_NOTES_FILE}" >/dev/null; then
  echo "::error::Cache section leaked into release notes file ${RELEASE_NOTES_FILE}"
  exit 1
fi

mv "${assets_tmp}" "${RELEASE_ASSETS_FILE}"
trap - EXIT

# ── Release identity ─────────────────────────────────────────────────────────
# Derived from the artifacts themselves, never from a workflow input: the
# matrix `kernel_source` input defaults to `auto`, which used to produce tags
# like marble-auto-r123.
if [[ "${#seen_kernel_source[@]}" -ne 1 ]]; then
  echo "::error::Artifacts disagree on kernel_source; refusing to build a release identity"
  exit 1
fi
release_kernel_source="${!seen_kernel_source[*]}"
if [[ "${#seen_rom_version[@]}" -gt 1 ]]; then
  echo "::error::Artifacts disagree on evolution_x_version"
  exit 1
fi
release_rom_version=""
[[ "${#seen_rom_version[@]}" -eq 1 ]] && release_rom_version="${!seen_rom_version[*]}"
release_droidspaces="false"
if [[ "${#seen_droidspaces[@]}" -eq 1 && "${!seen_droidspaces[*]}" == "true" ]]; then
  release_droidspaces="true"
elif [[ "${#seen_droidspaces[@]}" -gt 1 ]]; then
  echo "::error::Artifacts disagree on droidspaces_enabled"
  exit 1
fi

slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//'; }

release_kernel_slug="$(slugify "${release_kernel_source}")"
[[ -n "${release_kernel_slug}" ]] || release_kernel_slug="unknown"
release_rom_slug=""
[[ -n "${release_rom_version}" ]] && release_rom_slug="$(slugify "${release_rom_version}")"

if [[ -z "${RELEASE_METADATA_FILE:-}" ]]; then
  if [[ "${RELEASE_ASSETS_FILE}" == */* ]]; then
    RELEASE_METADATA_FILE="$(dirname "${RELEASE_ASSETS_FILE}")/release-metadata.env"
  else
    RELEASE_METADATA_FILE="release-metadata.env"
  fi
fi

tag_base="marble-${release_kernel_slug}"
[[ -n "${release_rom_slug}" ]] && tag_base+="-${release_rom_slug}"
[[ "${release_droidspaces}" == "true" ]] && tag_base+="-droidspaces"
[[ -n "${SOURCE_RUN_NUMBER}" ]] && tag_base+="-r${SOURCE_RUN_NUMBER}"

display="$(python3 - "${release_kernel_source}" <<'PY' 2>/dev/null || true
import json, sys
try:
    presets = json.load(open("config/kernel-sources.json", encoding="utf-8"))
except Exception:
    sys.exit(0)
print((presets.get(sys.argv[1]) or {}).get("display") or "")
PY
)"
[[ -n "${display}" ]] || display="${release_kernel_source}"

manager_label=""
for mgr in "${manager_order[@]}"; do
  [[ -n "${manager_label}" ]] && manager_label+=" + "
  manager_label+="${mgr}"
done
[[ -n "${manager_label}" ]] || manager_label="unknown"

title="${display}"
[[ -n "${release_rom_version}" ]] && title+=" ${release_rom_version}"
title+=" · ${manager_label}"
[[ "${release_droidspaces}" == "true" ]] && title+=" · Droidspaces"
[[ -n "${SOURCE_RUN_NUMBER}" ]] && title+=" · r${SOURCE_RUN_NUMBER}"

# %q: the workflow `source`s this file, so values with spaces (release_title)
# must be shell-quoted or sourcing tries to execute their second word.
{
  printf 'release_kernel_source=%q\n' "${release_kernel_source}"
  printf 'release_kernel_slug=%q\n' "${release_kernel_slug}"
  printf 'release_rom_version=%q\n' "${release_rom_version}"
  printf 'release_droidspaces=%q\n' "${release_droidspaces}"
  printf 'release_manager_label=%q\n' "${manager_label}"
  printf 'release_display=%q\n' "${display}"
  printf 'release_tag=%q\n' "${tag_base}"
  printf 'release_title=%q\n' "${title}"
} > "${RELEASE_METADATA_FILE}"

echo "Prepared $(wc -l < "${RELEASE_ASSETS_FILE}") verified release ZIP(s)"
echo "Release notes (no CI cache section): ${RELEASE_NOTES_FILE}"
echo "Release identity: tag=${tag_base} title=${title}"
echo "Release metadata: ${RELEASE_METADATA_FILE}"
