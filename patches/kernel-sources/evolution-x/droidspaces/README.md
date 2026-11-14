# Droidspaces GKI kABI patches — Evolution X / marble (kernel 5.10)

Vendored **verbatim** from the Droidspaces OSS project. Do not edit in place: if the
kernel tree changes, re-verify with `git apply --check` and replace the files.

| Field | Value |
|---|---|
| Source repo | https://github.com/ravindu644/Droidspaces-OSS |
| Source path | `Documentation/resources/kernel-patches/GKI/below-kernel-6.12/` |
| Fetched from | branch `main`, later verified byte-identical to tag **`v7.2.0`** (`cdadb9eb5d0f…`) |
| Fetched on | 2026-11-16 |
| Upstream version | **Droidspaces v7.2.0** (recorded in `config/kernel-sources.json` as `source_patches.version`) |

## Files

| File | SHA-256 | Applies to |
|---|---|---|
| `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` | `47fc945b2d73d9737d56c0f1c3a74cda0a95c30f9dc1b1abe546fa48940c4460` | task_struct KABI slots 6/7/8 (`CONFIG_SYSVIPC`) |
| `002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch` | `31982c85f4a65ca3ec71d27903626fb0234a39c4d3e99667bc849918e42693b7` | `struct user_struct` (`CONFIG_POSIX_MQUEUE`), 5.10 and older |

`series` order matters for review only; the two patches touch different files
(`include/linux/sched.h` and `include/linux/sched/user.h`).

## Why the `6_7_8` variant

`Evolution-X-Devices/kernel_xiaomi_sm8450@cnb` (5.10.269) `include/linux/sched.h`:

```
1390: ANDROID_KABI_USE(1, void *pf_io_worker);     ← slot 1 used by Android
1392: ANDROID_KABI_USE(2, struct { ... });          ← slot 2 used by Xiaomi
1397: ANDROID_KABI_RESERVE(3) … (8)                 ← 3–8 free
```

Measured with strict `git apply --check` (no fuzz) on 2026-11-16:

| Patch | 5.10 tree (`cnb`) |
|---|---|
| `…_1_2_3.patch` | ✗ reject |
| `…_3_4_5.patch` | ✗ reject |
| `…_6_7_8.patch` | ✓ applies |
| `002…posix_mqueue.patch` | ✓ applies |

## When these must be re-verified

- Kernel ref/commit changes (see `config/evolution-x-versions.json`).
- Upstream Droidspaces changes the patch files.
- Kernel moves to 6.6 (Evolution X 12.5+): the `6_7_8` hunk **fails** on the 6.6 tree
  (`#ifdef CONFIG_RV` replaced the upstream trailing context) and must be rebased.

## Gate

`config/kernel-sources.json` only applies this directory when
`ENABLE_DROIDSPACES=true` **and** `SOURCE_REF`/`SOURCE_REF_LABEL` matches `match_refs`.

## Removal

Delete the `source_patches` block from the `evolution-x` preset (or set
`"enabled": false`). `apply-kernel-source-patches.sh` then becomes a no-op again.