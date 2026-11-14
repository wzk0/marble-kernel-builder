#!/usr/bin/env bash
# Offline parsing tests for scripts/derive-kernel-pin.sh (no network).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

script=scripts/derive-kernel-pin.sh
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Real device string (Evolution X 12.4 / marble).
out="$(bash "${script}" --release '5.10.269-gki-g658b84f13496' --version 12.4 --no-resolve 2>/dev/null)"
grep -q '"kernel_version": "5.10.269"' <<<"${out}" || fail "kernel_version not parsed"
grep -q '"kernel_release_suffix": "-gki-g658b84f13496"' <<<"${out}" || fail "suffix not parsed"
grep -q '"12.4": {' <<<"${out}" || fail "version key not emitted"
grep -q 'unresolved' <<<"${out}" || fail "no-resolve must mark the commit as unresolved"

# A 40-char sha in the release string needs no network at all.
full=658b84f13496fa94659905e5f29b31cfde41d0ce
out="$(bash "${script}" --release "5.10.269-gki-g${full}" --version 12.4 2>/dev/null)" || fail "full-sha run failed"
grep -q "\"kernel_commit\": \"${full}\"" <<<"${out}" || fail "full sha not reused"

# -dirty suffix and 6.6 style release strings must parse too.
bash "${script}" --release '5.10.269-gki-g658b84f13496-dirty' --no-resolve >/dev/null 2>&1 \
  || fail "dirty suffix should parse"
bash "${script}" --release '6.6.144-4k-g1db41da4638c' --no-resolve >/dev/null 2>&1 \
  || fail "6.6 4k release should parse"

# Non CONFIG_LOCALVERSION_AUTO strings must be rejected, not guessed.
if bash "${script}" --release '5.10.269-android12-9' --no-resolve >/dev/null 2>&1; then
  fail "release string without -g<sha> must be rejected"
fi

# Missing input.
if bash "${script}" --no-resolve >/dev/null 2>&1; then
  fail "missing --release must be rejected"
fi

# Exit code 3 signals "parsed but the commit could not be resolved" so scripts can catch it.
# Both resolvers are shadowed by failing stubs, so this stays offline and deterministic.
shim="$(mktemp -d)"
trap 'rm -rf "${shim}"' EXIT
printf '#!/bin/sh\nexit 1\n' >"${shim}/gh"
printf '#!/bin/sh\nexit 1\n' >"${shim}/git"
chmod +x "${shim}/gh" "${shim}/git"
set +e
PATH="${shim}:${PATH}" bash "${script}" --release '5.10.269-gki-gabc123def456' >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -eq 3 ]] || fail "unresolved pin must exit 3 (got ${rc})"

echo "derive-kernel-pin tests passed"