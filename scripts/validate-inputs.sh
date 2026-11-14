#!/usr/bin/env bash
set -euo pipefail

MANAGER="${MANAGER:-none}"
ENABLE_SUSFS="${ENABLE_SUSFS:-false}"
BUILD_SCOPE="${BUILD_SCOPE:-image-only}"
SOURCE_REPO="${SOURCE_REPO:-}"
SOURCE_REF="${SOURCE_REF:-}"
KERNEL_SOURCE="${KERNEL_SOURCE:-}"
SUSFS_VERSION="${SUSFS_VERSION:-latest}"
SUSFS_KERNEL_BRANCH="${SUSFS_KERNEL_BRANCH:-gki-android12-5.10}"
SUSFS_REF="${SUSFS_REF:-}"
SUSFS_EXPECTED_VERSION="${SUSFS_EXPECTED_VERSION:-}"
MANAGER_REF="${MANAGER_REF:-}"
ENABLE_DROIDSPACES="${ENABLE_DROIDSPACES:-false}"
DROIDSPACES_PROFILE="${DROIDSPACES_PROFILE:-}"
KERNEL_COMMIT="${KERNEL_COMMIT:-}"
EVOLUTION_X_VERSION="${EVOLUTION_X_VERSION:-}"
SUSFS_KERNEL_BRANCH_MAPPED="${SUSFS_KERNEL_BRANCH_MAPPED:-}"

case "${MANAGER}" in
  none|kernelsu|kernelsu-next|sukisu-ultra|resukisu) ;;
  *) echo "::error::Unsupported manager: ${MANAGER}"; exit 1 ;;
esac

if [[ -n "${KERNEL_SOURCE}" ]]; then
  if [[ ! -f config/kernel-sources.json ]]; then
    echo "::error::config/kernel-sources.json is missing"
    exit 1
  fi
  if ! jq -e --arg k "${KERNEL_SOURCE}" '.[$k]' config/kernel-sources.json >/dev/null; then
    echo "::error::Unsupported kernel_source: ${KERNEL_SOURCE}" >&2
    echo "Allowed: $(jq -r 'keys | sort | join(", ")' config/kernel-sources.json)" >&2
    exit 1
  fi
fi

case "${ENABLE_SUSFS}" in
  true|false) ;;
  *) echo "::error::ENABLE_SUSFS must be true or false, got ${ENABLE_SUSFS}"; exit 1 ;;
esac

case "${BUILD_SCOPE}" in
  image-only|full) ;;
  *) echo "::error::BUILD_SCOPE must be image-only or full, got ${BUILD_SCOPE}"; exit 1 ;;
esac

LTO="${LTO:-thin}"
case "${LTO}" in
  none|thin|full) ;;
  *) echo "::error::LTO must be none, thin, or full, got ${LTO}"; exit 1 ;;
esac

if [[ "${LTO}" == "full" ]]; then
  echo "::warning::LTO=full is memory-heavy on free GitHub-hosted runners (~7GiB). Prefer thin unless on high-RAM hosts."
fi

if [[ "${MARBLE_DENY_FULL_LTO:-false}" == "true" && "${LTO}" == "full" ]]; then
  echo "::error::LTO=full is denied by MARBLE_DENY_FULL_LTO=true"
  exit 1
fi

if [[ -z "${SOURCE_REPO}" || ! "${SOURCE_REPO}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::error::SOURCE_REPO must look like owner/repo, got ${SOURCE_REPO}"
  exit 1
fi

if [[ -z "${SOURCE_REF}" || ! "${SOURCE_REF}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "::error::SOURCE_REF contains invalid characters: ${SOURCE_REF}"
  exit 1
fi

if [[ "${ENABLE_SUSFS}" == "true" && "${MANAGER}" == "none" ]]; then
  echo "::error::SUSFS requires a manager. Choose kernelsu, kernelsu-next, sukisu-ultra, resukisu, or custom."
  exit 1
fi

case "${SUSFS_VERSION}" in
  latest|v2.2.0|v2.1.0|custom) ;;
  *) echo "::error::SUSFS_VERSION must be latest, v2.2.0, v2.1.0, or custom, got ${SUSFS_VERSION}"; exit 1 ;;
esac

if [[ "${ENABLE_SUSFS}" == "true" ]]; then
  case "${MANAGER}" in
    kernelsu)
      echo "::error::Official tiann/KernelSU does not currently provide a SUSFS-integrated ref compatible with this builder. Disable SUSFS or choose another official manager."
      exit 1
      ;;
    kernelsu-next)
      [[ -z "${MANAGER_REF}" || "${MANAGER_REF}" == "dev-susfs" ]] || { echo "::error::KernelSU-Next + SUSFS requires pershoot dev-susfs ref"; exit 1; }
      ;;
    sukisu-ultra)
      [[ -z "${MANAGER_REF}" || "${MANAGER_REF}" == "builtin" ]] || { echo "::error::SukiSU Ultra + SUSFS requires official ref builtin"; exit 1; }
      ;;
    resukisu)
      [[ -z "${MANAGER_REF}" || "${MANAGER_REF}" == "main" ]] || { echo "::error::ReSukiSU + SUSFS requires official ref main"; exit 1; }
      ;;
  esac
  case "${SUSFS_KERNEL_BRANCH}" in
    gki-android12-5.10|gki-android15-6.6) ;;
    *)
      echo "::error::Unsupported SUSFS_KERNEL_BRANCH=${SUSFS_KERNEL_BRANCH} (expected gki-android12-5.10 for 5.10 kernels, gki-android15-6.6 for 6.6)"
      exit 1
      ;;
  esac
  if [[ -n "${SUSFS_KERNEL_BRANCH_MAPPED}" && "${SUSFS_KERNEL_BRANCH}" != "${SUSFS_KERNEL_BRANCH_MAPPED}" ]]; then
    echo "::error::SUSFS_KERNEL_BRANCH=${SUSFS_KERNEL_BRANCH} contradicts the ROM version mapping (${SUSFS_KERNEL_BRANCH_MAPPED})"
    exit 1
  fi
  if [[ "${SUSFS_VERSION}" == "custom" && -z "${SUSFS_REF}" ]]; then
    echo "::error::custom SUSFS_VERSION requires SUSFS_REF as branch/tag/commit"
    exit 1
  fi
  if [[ -n "${SUSFS_REF}" && ! "${SUSFS_REF}" =~ ^[A-Za-z0-9._/-]+$ ]]; then
    echo "::error::SUSFS_REF contains invalid characters: ${SUSFS_REF}"
    exit 1
  fi
  if [[ -n "${SUSFS_EXPECTED_VERSION}" && ! "${SUSFS_EXPECTED_VERSION}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::SUSFS_EXPECTED_VERSION must look like v2.2.0, got ${SUSFS_EXPECTED_VERSION}"
    exit 1
  fi
fi

case "${ENABLE_DROIDSPACES}" in
  true|false) ;;
  *) echo "::error::ENABLE_DROIDSPACES must be true or false, got ${ENABLE_DROIDSPACES}"; exit 1 ;;
esac

if [[ "${ENABLE_DROIDSPACES}" == "true" ]]; then
  if [[ -z "${DROIDSPACES_PROFILE}" ]]; then
    echo "::error::Droidspaces needs a version mapping (DROIDSPACES_PROFILE is empty). Select a kernel_source that resolves through config/evolution-x-versions.json."
    exit 1
  fi
  if [[ ! "${KERNEL_COMMIT}" =~ ^[0-9a-f]{40}$ ]]; then
    echo "::error::Droidspaces applies commit-specific kABI patches, so the kernel source must be pinned by commit (KERNEL_COMMIT is '${KERNEL_COMMIT}')"
    exit 1
  fi
  if [[ ! -f config/kernel-sources.json ]]; then
    echo "::error::config/kernel-sources.json is missing"
    exit 1
  fi
  patch_dir="$(jq -r --arg s "${KERNEL_SOURCE}" '.[$s].source_patches.dir // empty' config/kernel-sources.json)"
  patch_gate="$(jq -r --arg s "${KERNEL_SOURCE}" '.[$s].source_patches.requires_env // empty' config/kernel-sources.json)"
  if [[ -z "${patch_dir}" || "${patch_gate}" != "ENABLE_DROIDSPACES" ]]; then
    echo "::error::kernel_source '${KERNEL_SOURCE}' has no Droidspaces patch series (source_patches.requires_env=ENABLE_DROIDSPACES)"
    exit 1
  fi
  if [[ ! -f "${patch_dir}/series" ]]; then
    echo "::error::Missing Droidspaces patch series: ${patch_dir}/series"
    exit 1
  fi
  if ! grep -qvE '^\s*(#|$)' "${patch_dir}/series"; then
    echo "::error::Droidspaces patch series is empty: ${patch_dir}/series"
    exit 1
  fi
fi

echo "Input validation passed"
