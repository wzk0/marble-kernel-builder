#!/usr/bin/env bash
# Derive the kernel source pin for an Evolution X build from the ROM's own kernel
# release string. This is the only reliable way to reproduce the exact commit the
# ROM was built from: CONFIG_LOCALVERSION_AUTO appends "-g<short sha>" to the
# release, and a different commit changes vermagic, which makes every vendor_dlkm
# module refuse to load.
#
# Usage:
#   bash scripts/derive-kernel-pin.sh --release '5.10.269-gki-g658b84f13496' --version 12.5
#   bash scripts/derive-kernel-pin.sh --adb --version 12.5          # reads `adb shell uname -r`
#   bash scripts/derive-kernel-pin.sh --release ... --no-resolve    # parse only (no network)
#
# Output: a human summary plus a JSON block ready to paste into
#         config/evolution-x-versions.json under "versions".
set -euo pipefail

KERNEL_REPO_DEFAULT="Evolution-X-Devices/kernel_xiaomi_sm8450"
release=""
version=""
resolve=1
use_adb=0
repo="${KERNEL_REPO_DEFAULT}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --release) release="${2:-}"; shift 2 ;;
    --release=*) release="${1#*=}"; shift ;;
    --version) version="${2:-}"; shift 2 ;;
    --version=*) version="${1#*=}"; shift ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --repo=*) repo="${1#*=}"; shift ;;
    --adb) use_adb=1; shift ;;
    --no-resolve) resolve=0; shift ;;
    -h|--help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "::error::unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "${use_adb}" -eq 1 && -z "${release}" ]]; then
  ADB_BIN="${ADB_BIN:-adb}"
  if ! command -v "${ADB_BIN}" >/dev/null 2>&1; then
    echo "::error::adb not found; pass --release '<uname -r>' instead" >&2
    exit 1
  fi
  release="$("${ADB_BIN}" shell uname -r | tr -d '\r')"
fi

if [[ -z "${release}" ]]; then
  echo "::error::need --release '<uname -r>' or --adb" >&2
  exit 1
fi

# Examples we must accept:
#   5.10.269-gki-g658b84f13496
#   5.10.269-gki-g658b84f13496-dirty
#   6.6.144-4k-g1db41da4638c
if [[ ! "${release}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)[^[:space:]]*-g([0-9a-f]{7,40}) ]]; then
  echo "::error::cannot find '<x.y.z>...-g<sha>' in release string: ${release}" >&2
  echo "::error::CONFIG_LOCALVERSION_AUTO must be enabled in the ROM kernel for this to work" >&2
  exit 1
fi

kernel_version="${BASH_REMATCH[1]}"
short_sha="${BASH_REMATCH[2]}"
suffix="-${release#*-g}"
suffix="$(printf '%s' "${release}" | sed -E "s/^${kernel_version}//")"

commit=""
if [[ "${#short_sha}" -eq 40 ]]; then
  commit="${short_sha}"
  short_sha="${commit:0:12}"
elif [[ "${resolve}" -eq 1 ]]; then
  if command -v gh >/dev/null 2>&1; then
    commit="$(gh api "repos/${repo}/commits/${short_sha}" --jq .sha 2>/dev/null || true)"
  fi
  if [[ -z "${commit}" ]]; then
    # Fallback: ls-remote every branch and look for the prefix (works without gh auth).
    commit="$(git ls-remote --heads "https://github.com/${repo}.git" 2>/dev/null \
      | awk -v p="${short_sha}" 'index($1, p) == 1 { print $1; exit }' || true)"
  fi
fi

[[ "${#commit}" -eq 40 ]] || commit=""

{
  echo "kernel_version=${kernel_version}"
  echo "kernel_short_sha=${short_sha}"
  echo "kernel_release_suffix=${suffix}"
  echo "kernel_repo=${repo}"
  echo "kernel_commit=${commit}"
  echo "evolution_x_version=${version}"
} >&2

cat <<JSON
  "${version:-<version>}": {
    "kernel_repo": "${repo}",
    "kernel_ref": "<branch, e.g. cnb>",
    "kernel_commit": "${commit:-<40-char-sha: unresolved>}",
    "kernel_version": "${kernel_version}",
    "kernel_release_suffix": "${suffix}",
    "config_fragments": [
      "<copy from the matching device_xiaomi_sm8450-common TARGET_KERNEL_CONFIG>"
    ]
  }
JSON

if [[ -z "${commit}" ]]; then
  if [[ "${resolve}" -eq 1 ]]; then
    echo "::error::could not resolve ${short_sha} to a full commit in ${repo}" >&2
    exit 3
  fi
  echo "::warning::--no-resolve: kernel_commit left empty; fill it in before committing" >&2
fi