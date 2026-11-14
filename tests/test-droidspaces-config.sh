#!/usr/bin/env bash
# Policy tests for the Droidspaces integration:
#  - patch assets are present, unchanged, and listed in `series`
#  - the patch gate is opt-in (ENABLE_DROIDSPACES)
#  - build-kernel.sh turns on the required symbols and keeps kABI-breaking ones off
#  - validate-inputs.sh refuses Droidspaces without a pinned commit
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

PYTHON="${PYTHON:-python3}"
pdir=patches/kernel-sources/evolution-x/droidspaces
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# ── Patch assets ─────────────────────────────────────────────────────────────
for f in "${pdir}/series" "${pdir}/README.md" \
         "${pdir}/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch" \
         "${pdir}/002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch"; do
  [[ -f "${f}" ]] || fail "missing ${f}"
done

grep -qx '001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch' "${pdir}/series" \
  || fail "series must list the SYSVIPC kABI patch"
grep -qx '002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch' "${pdir}/series" \
  || fail "series must list the POSIX_MQUEUE kABI patch"

# Patches are vendored verbatim: checksum drift means someone edited them.
printf '%s  %s\n' \
  47fc945b2d73d9737d56c0f1c3a74cda0a95c30f9dc1b1abe546fa48940c4460 "${pdir}/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch" \
  31982c85f4a65ca3ec71d27903626fb0234a39c4d3e99667bc849918e42693b7 "${pdir}/002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch" \
  | sha256sum -c - >/dev/null || fail "Droidspaces patches must stay verbatim (checksum mismatch)"

grep -q 'ANDROID_KABI_USE(6, struct sysv_sem sysvsem)' \
  "${pdir}/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch" \
  || fail "SYSVIPC patch must use KABI slot 6"

# ── Preset wiring ────────────────────────────────────────────────────────────
"${PYTHON}" - <<'PY'
import json
from pathlib import Path

presets = json.loads(Path("config/kernel-sources.json").read_text(encoding="utf-8"))
sp = (presets["evolution-x"].get("source_patches") or {})
assert sp.get("enabled") is True, "evolution-x source_patches must be enabled"
assert sp.get("dir") == "patches/kernel-sources/evolution-x/droidspaces"
assert sp.get("requires_env") == "ENABLE_DROIDSPACES", "patches must be opt-in"
refs = sp.get("match_refs") or []
assert "cnb" in refs, "match_refs must accept the branch label"
assert any(len(r) == 40 for r in refs), "match_refs must accept the pinned commit"
assert presets["evolution-x"].get("version_map") is True
print("preset wiring ok")
PY

# ── Gate behaviour ───────────────────────────────────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/kernel-source"

# Opt-in unset -> skip, exit 0.
out="$(KERNEL_SOURCE=evolution-x SOURCE_REF=658b84f13496fa94659905e5f29b31cfde41d0ce \
  SOURCE_REF_LABEL=cnb KERNEL_DIR="${tmp}/kernel-source" \
  env -u ENABLE_DROIDSPACES bash scripts/apply-kernel-source-patches.sh)"
grep -qi 'opt-in\|Skipping' <<<"${out}" || fail "patches must be skipped when ENABLE_DROIDSPACES is unset"

# Fully disabled explicitly -> skip, exit 0.
out="$(KERNEL_SOURCE=evolution-x SOURCE_REF=658b84f13496fa94659905e5f29b31cfde41d0ce \
  SOURCE_REF_LABEL=cnb ENABLE_DROIDSPACES=false KERNEL_DIR="${tmp}/kernel-source" \
  bash scripts/apply-kernel-source-patches.sh)"
grep -qi 'opt-in\|Skipping' <<<"${out}" || fail "patches must be skipped when ENABLE_DROIDSPACES=false"

# Enabled but ref outside match_refs -> skip (branch moved past the pin).
out="$(KERNEL_SOURCE=evolution-x SOURCE_REF=deadbeefcafe1234 SOURCE_REF_LABEL=other \
  ENABLE_DROIDSPACES=true KERNEL_DIR="${tmp}/kernel-source" \
  bash scripts/apply-kernel-source-patches.sh)"
grep -qi 'Skipping' <<<"${out}" || fail "patches must be skipped for an unmapped ref"

# Enabled on an empty tree -> the patch must hard-fail (gate really opened).
if KERNEL_SOURCE=evolution-x SOURCE_REF=658b84f13496fa94659905e5f29b31cfde41d0ce \
   SOURCE_REF_LABEL=cnb ENABLE_DROIDSPACES=true KERNEL_DIR="${tmp}/kernel-source" \
   bash scripts/apply-kernel-source-patches.sh >/dev/null 2>&1; then
  fail "enabled patches must fail on a tree without the target hunks"
fi

# ── build-kernel.sh contract ─────────────────────────────────────────────────
for sym in SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS NETFILTER_XT_MATCH_ADDRTYPE; do
  grep -q -- "-e ${sym}" scripts/build-kernel.sh \
    || fail "build-kernel.sh must enable CONFIG_${sym} via scripts/config"
  grep -qF "${sym}" <(grep -F 'droidspaces_required=' scripts/build-kernel.sh) \
    || fail "build-kernel.sh must assert CONFIG_${sym} in the final .config"
done
for sym in CFS_BANDWIDTH CGROUP_PIDS; do
  grep -q -- "-d ${sym}" scripts/build-kernel.sh \
    || fail "build-kernel.sh must disable CONFIG_${sym}"
  grep -qF "# CONFIG_\${sym} is not set" scripts/build-kernel.sh \
    || fail "build-kernel.sh must assert CONFIG_${sym} stays off"
done

# ── validate-inputs contract ─────────────────────────────────────────────────
SOURCE_REPO=owner/repo SOURCE_REF=main KERNEL_SOURCE=evolution-x MANAGER=kernelsu \
  ENABLE_DROIDSPACES=true DROIDSPACES_PROFILE=gki-5.10 \
  KERNEL_COMMIT=658b84f13496fa94659905e5f29b31cfde41d0ce \
  bash scripts/validate-inputs.sh >/dev/null || fail "pinned + profiled Droidspaces build must validate"

if SOURCE_REPO=owner/repo SOURCE_REF=cnb KERNEL_SOURCE=evolution-x MANAGER=kernelsu \
   ENABLE_DROIDSPACES=true DROIDSPACES_PROFILE=gki-5.10 \
   bash scripts/validate-inputs.sh >/dev/null 2>&1; then
  fail "Droidspaces without a pinned commit must be rejected"
fi

if SOURCE_REPO=owner/repo SOURCE_REF=main KERNEL_SOURCE=melt MANAGER=kernelsu \
   ENABLE_DROIDSPACES=true DROIDSPACES_PROFILE=gki-5.10 \
   KERNEL_COMMIT=658b84f13496fa94659905e5f29b31cfde41d0ce \
   bash scripts/validate-inputs.sh >/dev/null 2>&1; then
  fail "Droidspaces on a preset without a patch series must be rejected"
fi

echo "Droidspaces policy tests passed"