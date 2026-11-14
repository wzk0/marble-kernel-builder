<!--
本文件是 Pi skill `project:marble-kernel-builder:marble-kernel-ci` 的仓库镜像（便于换机器/换 agent 复用）。
权威副本在：~/.pi/agent/projects-memory/marble-kernel-builder/skills/marble-kernel-ci/SKILL.md
改这份时请同步改那份（反之亦然），否则两边会漂移。
-->

---
name: "marble-kernel-ci"
description: "为 marble（Redmi Note 12 Turbo / Poco F5）接入或更新 Evolution X 内核的 GitHub Actions 构建：第一次把新设备/新 ROM 接上 CI、以及后续按 Evolution X / KernelSU / Droidspaces 版本号做增量更新。触发词：Evolution X 内核、marble kernel、uname -r 反推 commit、config/evolution-x-versions.json、gh workflow run build-matrix.yml、Droidspaces kABI、KernelSU 升级、Draft Release 审计。"
version: 1
created: "2026-11-14"
updated: "2026-11-14"
---
## When to Use
在仓库 marble-kernel-builder 内，当任务是下列之一时使用：
1) 首次接入：新机器/新 ROM（或换设备）要把「Evolution X 版本 → 内核源码 commit → CI 构建 → Draft Release」这条链跑通；
2) 版本更新：用户升级了 Evolution X、或告知/检测到新的 KernelSU 版本、或 Droidspaces 上游补丁变化，需要产出新内核；
3) 构建坏了：CI 红了、模块加载失败、开机异常，需要按症状定位是 pin/fragment/配置还是 ABI 问题。

不适用：给其它机型做内核、给 ROM 本体编译、刷机操作（刷机需用户另行明确授权，且本 skill 不含刷机步骤）。

## Procedure
1. 开仓库并读事实：`cd ~/Projects/marble-kernel-builder && git status -sb && git log -1 --oneline`，然后读 `AGENTS.md`（唯一权威）与 `config/*.json`、`docs/versions.md`。确认这是 fork 仓库且工作区干净。
2. 本地门禁先跑一遍确认基线绿：`bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh`、`shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 scripts/*.sh scripts/lib/*.sh tests/*.sh`、`actionlint`、`bash tests/test-*.sh`；缺工具跑 `bash scripts/dev-install-preflight-deps.sh`。
3. 采集设备事实（只读 adb，禁止猜测）：`adb shell 'getprop ro.evolution.build.version; getprop ro.build.version.release'`、`adb shell uname -r`、`adb shell 'zcat /proc/config.gz' > reports/evidence/evo-<ver>-stock-config.txt`、`adb shell 'pm list packages | grep -iE "ksu|resukisu"'`、`adb shell 'ls /vendor/lib/modules | wc -l'`。取不到的项列出来让用户提供。
4. 推导内核 pin：`bash scripts/derive-kernel-pin.sh --adb --version <X.Y>`，得到 kernel_version / kernel_release_suffix / 40 位 kernel_commit；它会校验 release 后缀末 12 位与 commit 前缀一致（vermagic 守卫）。
5. 确认分支与 defconfig 链：`gh api repos/Evolution-X-Devices/device_xiaomi_marble/contents/evolution.dependencies?ref=cnb --jq .content | base64 -d`，再取对应 device_xiaomi_sm8450-common 分支的 `BoardConfigCommon.mk`：有 `TARGET_KERNEL_CONFIG` → 5.10 风格的四件套 fragment；只有 `TARGET_KERNEL_VERSION := 6.6` → Kleaf 风格，fragment 是 `vendor/waipio_perf.config`。
6. 写映射：把块合并进 `config/evolution-x-versions.json`（kernel_repo/ref/commit、kernel_version、kernel_release_suffix、defconfig_mode、base_defconfig、config_fragments、droidspaces_profile、susfs_kernel_branch、official_toolchain），并把 `default` 指向该版本。同步 `config/kernel-sources.json` 的 `source_patches.match_refs`（加 commit 或保留分支名）。
7. 首次接入时补齐 manager 与功能开关：`config/managers.json` 里 manager 的 `default_ref`（KernelSU 用 tag，如 `v3.3.1`）；Droidspaces 由 `enable_droidspaces` 控制，补丁目录 `patches/kernel-sources/evolution-x/droidspaces/` 必须与内核大版本匹配（5.10 用 `001…6_7_8` + `002…posix_mqueue`；6.6 需重制 001）。
8. 门禁 + 提交：`bash tests/test-*.sh`（20 个）、shellcheck、actionlint、`git diff --check` 全绿后 `git add` 并写清晰的 commit；未经用户同意不要 push。用户同意后 `git push origin main`，等 `Marble Builder Preflight` 变绿。
9. 先跑 S1（只要内核，验 pin/fragment/工具链）：`gh workflow run build-matrix.yml -f build_source_melt=false -f build_source_evolution_x=true -f build_none=true -f build_kernelsu=false -f enable_droidspaces=false -f evolution_x_version=<X.Y> -f toolchain=auto -f lto=thin -f build_scope=image-only -f create_draft_release=false`。
10. S1 产物验收（关键）：`gh run download <run-id> -D /tmp/s1`，然后 `diff <(grep -E '^(CONFIG_|# CONFIG_)' reports/evidence/evo-<ver>-stock-config.txt | sort) <(grep -E '^(CONFIG_|# CONFIG_)' /tmp/s1/*/config.txt | sort)`；除编译器版本号、`LTO_CLANG_THIN/FULL`、`UAPI_HEADER_TEST` 外不应有差异。有差异就停下查 fragment 链与 commit。
11. 再跑完整形态：同一条 `gh workflow run`，改成 `build_none=false build_kernelsu=true enable_droidspaces=true create_draft_release=true`；预期只多出 `CONFIG_KSU*`、`SYSVIPC*`、`POSIX_MQUEUE*`、`IPC_NS`、`PID_NS`、`DEVTMPFS*`、`XT_MATCH_ADDRTYPE`。
12. 审计产物并汇报：`jq . build-info.json`（rom/kernel/droidspaces/config_sha256 齐全）、`unzip -l *.zip`（27 条目、含 Image、无 vendor_boot/dtbo/.ko）、`sha256sum -c`、`gh release view <tag>`（Draft、tag/title 含 ROM 版本与 Droidspaces、notes 无 Cache 段）。
13. 版本更新时按类型分流：Evolution X → 重复步骤 3~11（只需改映射一个块）；KernelSU → 只改 `config/managers.json` 的 `default_ref` + `docs/versions.md`，然后重跑（预期冷缓存约 20 分钟）；Droidspaces → 只有上游内核补丁变了才动：替换补丁文件、先 `git apply --check` 验严格通过、同步 README 与测试里的 SHA256。
14. 刷机验证属于用户决策：不要自行 adb/fastboot 写分区。用户授权并刷入后，用 `adb shell uname -r`（应等于目标 release）、`adb shell 'su -c "dmesg | grep -iE \"disagrees about version|Unknown symbol\""'`（应为空）、KernelSU Manager 状态、Droidspaces Requirements 自检来判定；把结论写进 `reports/build-audit.md`。

## Pitfalls
- 绝不要用分支 HEAD 构建：`CONFIG_LOCALVERSION_AUTO=y` 让 vermagic 带 `-g<commit>`，commit 一变则 vendor_dlkm 的 396 个模块全部拒载（现象是不开机/黑屏/无 WiFi），但 CI 仍显示成功。
- fragment 链随内核大版本变：5.10 是 `gki_defconfig + waipio_GKI + xiaomi_GKI + marble_GKI + debugfs`；6.6 树里 `waipio_GKI.config`/`debugfs.config` 不存在，实际用 `vendor/waipio_perf.config`。填错会在 `Missing config fragment` 处失败，或更糟——编出 ABI 不一致的内核。
- `lto=none` 会连带关掉 `CONFIG_CFI_CLANG`（Kconfig 依赖 LTO），偏离官方配置；用 `thin`。
- 禁止开 `CONFIG_CFS_BANDWIDTH` / `CONFIG_CGROUP_PIDS`：改 scheduler/cgroup 结构会让数千导出符号 CRC 变化，无 padding 可救，必 bootloop；也不要关 `CONFIG_MODVERSIONS`。
- `CONFIG_IPC_NS` 依赖 `SYSVIPC` 或 `POSIX_MQUEUE`，只开 IPC_NS 会在 olddefconfig 后消失。断言要看最终 `out/.config`，不能只看 defconfig 文本。
- Droidspaces 补丁按内核大版本不同：5.10 用 `001…6_7_8`（task_struct 槽 6/7/8 空闲）+ `002…posix_mqueue`；6.6 树上 `001…6_7_8` 的 hunk#2 打不上（尾部上下文被 `#ifdef CONFIG_RV` 替换），必须重制。不要在 CI 里现下载上游补丁，要原样入库并记录 SHA256。
- `resolve-refs.sh` 解析 tag 时 awk 必须 `print $2`：裸 `print` 在 `sub()` 改过 `$2` 后会输出 `<sha> <tag>`，被 source 时炸成 `<tag>: command not found`，还会污染 ccache key 与 ZIP 名。
- 写要 `source` 的环境文件时用 `printf %q`：含空格的值（release title）会被当命令执行，报 `12.4: command not found`。
- GitHub runner 的 `/mnt` 是独立小盘：`df /` 显示 88 GiB 空闲也可能 fallocate 16 GiB 失败。swap 步骤要探测目标文件系统、按可用空间收缩、必要时 `dd` 回落，且失败只告警。
- release tag/title 不要取自 `inputs.kernel_source`（默认值是 `auto`，会生成 `marble-auto-rN`）；要从 artifact 的 `build-info.txt` 派生并写进 `release-metadata.env`。
- 测试顺序敏感性：早期 `test-toolchain-auto.sh` 会在仓库根留 `release/kernel-source.env`。若本地出现该目录先 `rm -rf release` 再跑全套，否则 `test-package-naming.sh` 会假失败。
- 不要把 `evolution_x_version` 的默认值同时写进 workflow 和 JSON：workflow 输入留空表示「用 mapping 的 default」，只有一处真源。
- 只在 `adb` 上做只读操作。刷机、`fastboot flash`、`dd` 写分区、改槽位/vbmeta 一律需要用户明确授权——本 skill 不执行这些。

## Verification
1. 本地门禁全绿：`bash -n` / `shellcheck` / `actionlint` / `bash tests/test-*.sh`（20 个）/ `git diff --check`。
2. 推送后 `Marble Builder Preflight` run 结论为 success。
3. S1 的 config diff 只剩编译器版本号、`LTO_CLANG_THIN/FULL`、`UAPI_HEADER_TEST`（关键项 `LOCALVERSION=-gki`、`LOCALVERSION_AUTO=y`、`MODVERSIONS=y`、`CFI_CLANG=y`、`ARCH_WAIPIO=y`、`BUILD_ARM64_DT_OVERLAY=y` 与真机一致）。
4. 完整构建的 config diff 只多出预期的 KernelSU/Droidspaces 项，且 `CFS_BANDWIDTH`/`CGROUP_PIDS` 仍为 not set。
5. artifact 审计通过：`zip-audit.txt` 27 条目、`file Image` = ARM64 boot executable、`build-info.json` 的 rom/kernel/droidspaces/config_sha256 齐全、`.sha256` 与实算一致。
6. Draft Release 存在且为 Draft：tag 形如 `marble-evolution-x-<ver>[-droidspaces]-r<run>`，title 含 ROM 版本与 Droidspaces，notes 无 Cache 段，资产只有 ZIP。
7. 设备侧（用户授权刷入后）：`adb shell uname -r` 等于目标 release；dmesg 无 `disagrees about version`/`Unknown symbol`；KernelSU Manager 显示 working 且版本 code 与 ZIP 名一致；Droidspaces Requirements 全绿（`--cpus`/`--pids-limit` 灰色属预期）。