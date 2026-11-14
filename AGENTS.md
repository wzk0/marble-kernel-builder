# AGENTS.md — Marble 内核 CI（Evolution X / KernelSU / Droidspaces）

面向将来接手本仓库的 agent。本文件合并了最初的任务书（原 `droidspaces-AGENTS.md`）与 2026-11 的实施经验。
**机器可验证的事实以 `config/*.json`、`docs/versions.md`、`reports/evidence/` 为准；本文解释为什么。**

> 操作型流程（首次接入 / 版本更新）另见 skill：`marble-kernel-ci`。

---

## 1. 目标与边界

用 GitHub Actions 为 **Redmi Note 12 Turbo / Poco F5（marble）** 编译 Evolution X 的内核，
产出 AnyKernel3 刷机包 + Draft Release。**Fedora 主机只做仓库维护、静态检查、触发 CI、审计产物。**

| 做 | 不做 |
|---|---|
| 改配置/脚本/workflow，跑本地门禁，dispatch Actions，下载审计 artifact | 在本地编译内核、搭第二套构建系统、手搓刷机包 |
| 需要时用 `adb` **只读**采集设备信息 | 自动刷机、`fastboot flash`、改槽位/vbmeta、清数据、改 Root 配置 |
| 修改前先读现状，优先复用既有脚本 | 重写 `resolve-*` / `build-kernel` / `package-anykernel` 等已验证组件 |

**只有用户明确授权才进刷机阶段。**

---

## 2. 硬事实基线（2026-11 真机实测，改动前先复核）

| 项 | 值 | 证据 |
|---|---|---|
| 设备 | `marble`（Redmi Note 12 Turbo / POCO `23049RAD8C`），slot `_a` | `getprop ro.product.device` |
| ROM | **Evolution X 12.4** = Android **17**，manifest 分支 **`cnb`** | `ro.evolution.build.version`、`Evolution-X/OTA@cnb/builds/marble.json` |
| 内核 | **5.10.269**，release `5.10.269-gki-g658b84f13496` | `adb shell uname -r` |
| 内核源码 | `Evolution-X-Devices/kernel_xiaomi_sm8450` @ **`658b84f13496fa94659905e5f29b31cfde41d0ce`**（分支 `cnb`） | `uname -r` 的 `-g` 后缀（`CONFIG_LOCALVERSION_AUTO=y`） |
| defconfig 链 | `gki_defconfig` + `vendor/{waipio_GKI,xiaomi_GKI,marble_GKI,debugfs}.config` | `device_xiaomi_sm8450-common@cnb` 的 `TARGET_KERNEL_CONFIG` + 真机 `/proc/config.gz` |
| 官方工具链 | AOSP clang **r563880c**（LLVM 21.0.0）；仓库默认 `llvm-22.1.8` | `cat /proc/version` |
| Root | **KernelSU**，pin tag **`v3.3.1`**（`0c0fdb96…`） | `config/managers.json` |
| 容器 | **Droidspaces** 开；SUSFS **关**（默认且本轮不需要） | `config/kernel-sources.json` 的 `source_patches.requires_env` |
| 真机 config 快照 | `reports/evidence/marble-12.4-stock-config.txt`（6249 项） | 设备 `/proc/config.gz`（**444 世界可读，无需 root**） |

### 2.1 为什么内核 commit 必须钉死（最容易踩的坑）

`CONFIG_LOCALVERSION_AUTO=y` → 模块 `vermagic` 里带完整 release 串（含 `-g<commit>`）。
换 commit 编出来的内核 → release 变成 `-g<别的sha>` → **vendor_boot / vendor_dlkm 里那 396 个模块全部拒载**
（现象：不开机 / 黑屏 / 无 WiFi），而 CI 仍然"编译成功"。

所以：**不要用分支 HEAD 构建**，用 `uname -r` 反推 commit 写进 `config/evolution-x-versions.json`。
resolver 内置守卫：`kernel_release_suffix` 末 12 位必须等于 `kernel_commit` 前缀，不一致直接失败。

### 2.2 设备信息采集（只读，不要猜）

```bash
adb devices -l

adb shell '
getprop ro.product.device; getprop ro.product.model; getprop ro.board.platform
getprop ro.evolution.build.version; getprop ro.evolution.version; getprop ro.modversion
getprop ro.build.display.id; getprop ro.build.version.release; getprop ro.build.version.sdk
getprop ro.build.version.security_patch; getprop ro.build.date.utc; getprop ro.build.fingerprint
uname -a; cat /proc/version
getprop ro.boot.slot_suffix; getprop ro.boot.verifiedbootstate; getprop ro.boot.vbmeta.device_state
'

# 官方内核配置（不需要 root，Evo X 上是 444）
adb shell 'zcat /proc/config.gz' > reports/evidence/evo-<ver>-stock-config.txt

# 根状态 / vendor 模块
adb shell 'ls /sys/module | grep -iE "kernelsu|susfs"; pm list packages | grep -iE "ksu|resukisu|bakasu"; ls /vendor/lib/modules | wc -l'
```

取值写进 `reports/device-info.md`；**取不到的项就列出来让用户提供，不得推测**。
`/proc/config.gz` 是判断内核版本、fragment 链与 kABI 基线最省事的真值来源，**升级 ROM 后第一件事就是抓它**。

---

## 3. 仓库结构（复用优先，别重写）

```
.github/workflows/
  build-matrix.yml   唯一用户入口（workflow_dispatch）；setup → build[*] → aggregate → release
  build-core.yml     workflow_call：resolve → validate → checkout → toolchain → patch → build → package → audit
  preflight.yml      push/PR 静态门（bash -n / shellcheck / actionlint / 全部 tests / whitespace）
config/
  evolution-x-versions.json  ★ ROM 版本 → 内核 commit/fragment/工具链 的唯一真源
  kernel-sources.json        preset（repo/ref/fragments/source_patches）
  managers.json              root manager 白名单（KernelSU 已 pin tag）
  marble.env                 工具链 URL/SHA、AnyKernel3 pin 等常量
  susfs-refs.json            SUSFS 版本 → commit（当前未启用）
scripts/
  resolve-kernel-source.sh        ★ 读 mapping，输出 SOURCE_REF=<commit> + SOURCE_REF_LABEL=<branch>
  derive-kernel-pin.sh            ★ 从 `uname -r` 反推内核 pin（升级 ROM 的第一条命令）
  validate-inputs.sh              组合合法性（Droidspaces 需 pin+profile+补丁序列；SUSFS 分支白名单）
  apply-kernel-source-patches.sh  preset 级补丁（requires_env 门控；match_refs 接受 branch 或 commit）
  build-kernel.sh                 defconfig/LTO/Droidspaces 配置 + 终态断言
  package-anykernel.sh            AnyKernel3 + ZIP 命名
  prepare-promoted-release.sh     校验 artifact → 写 release-metadata.env（tag/title 由此派生）
  write-build-info-json.sh        provenance（rom.* / kernel.* / droidspaces.* / config_sha256）
patches/kernel-sources/evolution-x/droidspaces/   Droidspaces GKI kABI 补丁（原样入库 + SHA256 + README）
tests/                     20 个策略/回归测试，preflight 全跑
reports/                   preflight-report.md（审查+实施记录） + evidence/（真机 config 等）
```

设计约束：build job 只读（`contents: read`），写权限只在 release job；Actions 全部按 commit SHA 钉住；
逻辑放脚本、workflow 只编排；**不要新增第二套构建 workflow**（`tests/test-workflow-policy.sh` 会拦）。

---

## 4. 默认构建形态

```
Source      : evolution-x（默认勾选）      Manager : KernelSU（默认勾选）
Droidspaces : 开                          SUSFS   : 关
Toolchain   : auto → llvm-22.1.8          LTO     : thin（不要 none：会连带关掉 CFI_CLANG）
Scope       : image-only                  Release : create_draft_release 默认开
Scope 说明  : image-only 只出 boot 的 Image；不要宣称 vendor_boot/dtbo 被更新
```

```bash
gh workflow run build-matrix.yml \
  -f build_source_melt=false -f build_source_evolution_x=true \
  -f build_none=false -f build_kernelsu=true \
  -f enable_droidspaces=true -f enable_susfs=false \
  -f evolution_x_version=12.4 -f toolchain=auto -f lto=thin \
  -f build_scope=image-only -f enable_ccache=true \
  -f create_draft_release=true
```

产物：`AK3_marble_LOS_evolution-x_kernelsu-v3.3.1-code32680_rN.zip`
Draft tag：`marble-evolution-x-12.4-droidspaces-rN`，title：`Evolution-X 12.4 · kernelsu · Droidspaces · rN`

---

## 5. 版本更新 SOP

### 5.1 Evolution X 升级（如 12.4 → 12.5）——**唯一"要干活"的一种**

1. 升级 ROM，进系统后采集（§2.2）：`uname -r`、`/proc/config.gz`、`ro.evolution.build.version`。
2. 反推 pin：`bash scripts/derive-kernel-pin.sh --adb --version 12.5`（输出可直接粘贴的 JSON 块）。
3. 确认分支与 fragment 链（大版本可能变）：
   ```bash
   gh api repos/Evolution-X-Devices/device_xiaomi_marble/contents/evolution.dependencies?ref=cnb --jq .content | base64 -d
   # 5.10 → device_xiaomi_sm8450-common@cnb 有 TARGET_KERNEL_CONFIG（4 个 fragment）
   # 6.6  → device_xiaomi_sm8450-common@cnb-6.6 无该项，Kleaf 用 vendor/waipio_perf.config
   ```
4. 改 `config/evolution-x-versions.json` 一个块（commit / release_suffix / fragments / droidspaces_profile /
   susfs_kernel_branch / official_toolchain），并把 `default` 指向新版本。**这是唯一必须手改的文件。**
5. 同步 `config/kernel-sources.json` 的 `source_patches.match_refs`（加新 commit 或保留分支名）。
6. 本地门禁 → commit → push → 先跑 **S1（`none` + `enable_droidspaces=false`）** → 下载 artifact，
   把 `config.txt` 与真机 config 逐项 diff（见 §10）；通过后再跑完整 KernelSU + Droidspaces + Draft。
7. **若新版本内核 commit 与旧版相同**：不必重建，确认 config 与补丁一致后直接复用旧 ZIP。

**5.10 → 6.6 迁移的额外动作**：Droidspaces `001…6_7_8.patch` 的 hunk#2 在 6.6 树上打不上（尾部上下文被
`#ifdef CONFIG_RV` 替换）→ 需重制；SUSFS 分支改 `gki-android15-6.6`；`LOCALVERSION` 由 `-gki` 变 `-4k`。

### 5.2 KernelSU 升级——**改一行**

```bash
gh api repos/tiann/KernelSU/tags --jq '.[0:3][] | "\(.name) \(.commit.sha)"'
```

改 `config/managers.json` 的 `kernelsu.default_ref`（`notes` 里的 commit 一并更新）+ `docs/versions.md` 一行
→ `bash tests/test-*.sh` → push → dispatch。
副作用：ccache key 含 `manager_commit` → **这一次冷启动（~20 min）**，之后恢复 ~11 min。
ZIP 名自动带新版本与 code，无需改命名逻辑。

### 5.3 Droidspaces 升级——**多数情况什么都不用做**

- 只是 APK/CLI 更新 → 内核不动，装新 APK。
- 上游内核补丁变了（`ravindu644/Droidspaces-OSS` 的 `Documentation/resources/kernel-patches/GKI/below-kernel-6.12/`）：
  1. 替换 `patches/kernel-sources/evolution-x/droidspaces/` 下文件；
  2. 先在 pin 的 commit 树上 `git apply --check`（严格无 fuzz）通过；
  3. 更新该目录 `README.md` 的 SHA256 表 + `tests/test-droidspaces-config.sh` 里写死的两个 hash；
  4. 本地测试 → push → dispatch。

### 5.4 例行体检（每 2–4 周）

| 检查 | 命令 |
|---|---|
| 新 KernelSU / Droidspaces / SUSFS | `gh release list -R tiann/KernelSU`、`git ls-remote --heads https://gitlab.com/simonpunk/susfs4ksu.git` |
| 源码级补丁是否该移除 | 各 `patches/kernel-sources/**/README.md` 的"何时移除"段 |
| ccache 命中率 | artifact 的 `ccache-stats.txt` / summary 的 Cache 段 |
| 缓存体积 | GitHub → Actions → Caches |

---

## 6. 执行阶段（Phase 0–5）

| 阶段 | 内容 | 产出 | 门禁 |
|---|---|---|---|
| **P0 审查** | 仓库状态、workflow、脚本、config、设备事实、源码映射 | `reports/preflight-report.md` | 不改代码、不触发 |
| **P1 适配** | 版本映射、manager、Droidspaces、Release 身份、workflow 输入 | 代码 + 20 个测试全绿 | 本地门禁全绿 |
| **P2 首次构建** | S1（纯内核）→ 完整（KernelSU+Droidspaces+Draft） | Actions 产物 | S1 的 config diff 收敛 |
| **P3 产物审计** | ZIP 结构 / 镜像类型 / build-info / SHA256 / Release 内容 | `reports/build-audit.md` | artifact 全项核对 |
| **P4 设备验证** | 刷机、开机、模块加载、KernelSU、Droidspaces 自检 | 结论 | **需用户明确授权** |

---

## 7. 排错手册（含本项目真实踩过的坑）

| 症状 | 根因 | 处理 |
|---|---|---|
| `resolved-refs.env: line N: <tag>: command not found` | `resolve-refs.sh` tag 解析用裸 `print`，`sub()` 改 `$2` 会重建 `$0` → 值成 `<sha> <tag>` | 两个 awk 分支必须 `print $2`（已有静态断言） |
| `release-metadata.env: line N: 12.4: command not found` | 环境文件里写了带空格的值，`source` 时被拆成命令 | 一律 `printf %q`；测试里真的 `source` 回读 |
| `Setup swap for LTO` → `fallocate: No space left on device`（`df /` 却显示 88 GiB） | runner 的 `/mnt` 是独立小盘，旧实现写死 16 GiB 落 `/mnt` | 已改为探测 `/mnt` 与 `/`、按空间收缩、`dd` 回落、失败只告警 |
| `Missing config fragment` | fragment 列表与内核树不匹配（5.10 四件套 vs 6.6 的 `waipio_perf.config`） | 按 §5.1 第 3 步查 `TARGET_KERNEL_CONFIG` |
| `Droidspaces requires CONFIG_x=y` | 配置块没生效；`IPC_NS` 依赖 `SYSVIPC`/`POSIX_MQUEUE` | 看 `out/.config` 终态，不要只看 defconfig |
| `CONFIG_CFS_BANDWIDTH must stay disabled` | 有人开了 CPU/PID 限制 | 禁止：改 sched/cgroup 结构 → 数千符号 CRC 变化 → vendor 模块拒载 |
| 构建成功但不开机 / 模块拒载 | commit 漂移（vermagic 变）或 fragment 链错 | 用 `derive-kernel-pin.sh` 重钉；S1 的 config diff 会暴露 |
| `gh release create` 报 tag 已存在 | 同一 run number 重复 | 换新 run；Draft 可按需清理，**已发布** Release 删除需用户同意 |
| armv9 相关编译错误 | 用了 `android-r416183b`（clang 12） | 用 `llvm-22.1.8`（`toolchain=auto` 已保证） |
| 本地测试莫名失败 | 早期有测试在仓库根留 `release/kernel-source.env` | 已隔离；若残留先 `rm -rf release` 再跑全套 |

历史记录：`docs/verification/*.md`、`reports/preflight-report.md` §16–17。

---

## 8. 安全与边界（硬规则）

- **不自动刷机**：不 `fastboot flash`、不 `adb shell dd` 写分区、不改活动槽/vbmeta、不清数据、不动 Root 模块。
- 刷机前必须有 `boot` / `vendor_boot` / `dtbo` 备份（用户已持有全分区镜像）。
- **SUSFS 默认关闭**；Droidspaces 官方文档明确要求不自动切换 Root 方案、不改动现有 Root 配置。
  若用户正在使用 SUSFS，先说明冲突并取得同意。
- `sudo` 需密码；**禁止**把密码写进命令行/脚本/对话。需要 root 的写操作 → 写成脚本让用户自己跑。
- 删除/覆盖**已发布** Release 需用户同意；Draft 可以清理，但要先说明。
- 密钥 / API key 明文存本地配置（权限 600）是预期设计；不贴进聊天、不改成加密。
- 动作前：`git status --short`、`git log -1`；不覆盖用户未提交的改动；不擅自 push / 打 tag / 删分支。
- 修改后必须：`bash tests/test-*.sh` + `shellcheck` + `actionlint` + `git diff --check` 全绿，再看 `git diff`。

---

## 9. 本地门禁（等价 preflight.yml）

```bash
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 scripts/*.sh scripts/lib/*.sh tests/*.sh
actionlint
bash tests/test-*.sh
git diff --check
```

装依赖：`bash scripts/dev-install-preflight-deps.sh`（`patch`/`ShellCheck` 走 dnf；`actionlint` 1.7.12 放
`~/.local/bin`，与 CI 版本一致）。

---

## 10. 产物与验收

### 10.1 产物清单（artifact 内）

`*.zip`、`*.zip.sha256`、`build-info.txt`、`build-info.json`、`summary.md`、`zip-audit.txt`、
`ccache-stats.txt`、`zip-name.env`、**`config.txt`（最终 `.config`，用于与真机 config 对比）**。

### 10.2 验收标准

| 阶段 | 判定 |
|---|---|
| CI 构建 | 全 job 绿；ZIP 审计 27 条目；`Image` = `ARM64 boot executable Image` |
| **配置正确性** | CI 的 `config.txt` 与真机 config diff **只剩**：编译器版本号、`LTO_CLANG_THIN/FULL`、以及我们主动开启的项（`CONFIG_KSU*`、`SYSVIPC*`、`POSIX_MQUEUE*`、`IPC_NS`、`PID_NS`、`DEVTMPFS*`、`XT_MATCH_ADDRTYPE`） |
| 产物审计 | `build-info.json` 的 rom/kernel/droidspaces 字段齐全；`zip_sha256` 与 `.sha256` 一致 |
| Draft Release | tag/title 含 ROM 版本与 Droidspaces；notes 无 Cache 段；仅 ZIP 资产 |
| 设备验证 | `uname -r` == 目标 release；`dmesg` 无 `disagrees about version` / `Unknown symbol`；KernelSU Manager working；Droidspaces Requirements 全绿 |

**CI 成功 ≠ 内核通过验证**：只有刷机跑通才算。

### 10.3 AnyKernel ZIP 的行为（审计要点）

`block=boot`、`is_slot_device=auto`、`patch_vbmeta_flag=auto`、`do.modules=0`、`do.devicecheck=1`（marble/marblein）；
`dump_boot` 前先把当前 `boot` 备份到 `/sdcard/marble-kernel-backup/boot-marble-<slot>-<时间>.img`。
ZIP 内只有 `Image`，**不含** vendor_boot/dtbo/`.ko` → vendor 侧保持 ROM 原样（靠 vermagic 一致加载）。

---

## 11. 当前状态与未验证项

已完成：内核映射钉死、KernelSU 集成、Droidspaces 补丁与配置、Release 身份修正；
S1 与 r6 两次 CI 全绿；Draft `marble-evolution-x-12.4-droidspaces-r6`。

未验证（需刷机）：`llvm-22.1.8` 产出的内核在真机上是否被 vendor 模块接受；Droidspaces 容器实际能否启动；
KernelSU Manager 与内核 v3.3.1 的配合。

备选：官方内核用 **clang r563880c**，异常时可加工具链 preset（分支 `temp-android16-plus`，
sparse path `clang-r563880c`，需在 `marble.env` 加 URL/分支/commit，并在 `build-core.yml` 的 cache key 与 select 步骤加分支）。

---

## 12. 附录 A：Droidspaces 内核配置清单（5.10 / 12.4 实测）

**必须为 y（缺失则由 `build-kernel.sh` 打开并断言）**

```
CONFIG_SYSVIPC  CONFIG_POSIX_MQUEUE  CONFIG_IPC_NS  CONFIG_PID_NS  CONFIG_DEVTMPFS
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
```

**官方内核已是 y（不要动）**

```
CONFIG_NAMESPACES  CONFIG_UTS_NS  CONFIG_NET_NS  CONFIG_SECCOMP  CONFIG_SECCOMP_FILTER  CONFIG_SYSCTL
CONFIG_CGROUPS  CONFIG_MEMCG  CONFIG_CGROUP_FREEZER  CONFIG_CGROUP_NET_PRIO
CONFIG_BLK_DEV_LOOP  CONFIG_EXT4_FS  CONFIG_FUSE_FS  CONFIG_OVERLAY_FS  CONFIG_TUN  CONFIG_VETH  CONFIG_BRIDGE
CONFIG_NETFILTER  CONFIG_IP_NF_IPTABLES  CONFIG_NF_NAT  CONFIG_MODVERSIONS  CONFIG_CFI_CLANG
```

**必须保持关闭（kABI 会被破坏，无 padding 可救）**

```
CONFIG_CFS_BANDWIDTH   CONFIG_CGROUP_PIDS
```

**可选（默认不开；动了要评估 ABI）**：`USER_NS`、`MACVLAN`、`IP6_NF_NAT`、`IP6_NF_TARGET_MASQUERADE`、
`TMPFS_XATTR`、`TMPFS_POSIX_ACL`、`IP_SET*`、`NETFILTER_XT_MATCH_RECENT`。
`CONFIG_CGROUP_DEVICE` / `CONFIG_NF_TABLES` 仅出现在官方**非 GKI** 清单里，GKI 下不要为了它冒险。

kABI 补丁：`001…fix_sysvipc_kabi_6_7_8`（task_struct 槽 6/7/8）+ `002…posix_mqueue`（5.10 及更旧）；
6.12+ 换 `kernel-6.12/` 目录下那一个。

---

## 13. 附录 B：官方参考资料

| 用途 | 链接 |
|---|---|
| 构建器（上游） | https://github.com/mohdakil2426/marble-kernel-builder |
| Droidspaces 内核配置 | https://www.droidspaces.org/docs/kernel-configuration.html |
| Droidspaces 安装 | https://www.droidspaces.org/docs/installation-android.html |
| Droidspaces 补丁源（真实仓库） | https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches |
| KernelSU | https://github.com/tiann/KernelSU |
| Evolution X manifest | https://github.com/Evolution-X/manifest （分支 `vic`=A15 / `bka`=A16 / `cnb`=A17） |
| Evolution X OTA 元数据 | https://github.com/Evolution-X/OTA （`builds/marble.json` 给出真实版本号与文件名） |
| marble 设备树 | https://github.com/Evolution-X-Devices/device_xiaomi_marble |
| 内核源码 | https://github.com/Evolution-X-Devices/kernel_xiaomi_sm8450 |

**核对优先级**：仓库当前代码与官方实际发布内容 > 历史说明（含本文件）。

---

## 14. 文档索引

| 文件 | 内容 |
|---|---|
| `README.md` | 用户向：输入表、默认值、ZIP 命名、Draft Release |
| `docs/versions.md` | 所有 pin（含 12.4 内核 commit、KernelSU tag、工具链）与 vermagic 说明 |
| `docs/ARCHITECTURE.md` | 分层/管线/缓存设计 |
| `reports/preflight-report.md` | 完整审查 + Phase 2/3 记录（含 CI 事故复盘） |
| `reports/evidence/marble-12.4-stock-config.txt` | 真机内核配置原件（config diff 基准） |
| `patches/kernel-sources/evolution-x/droidspaces/README.md` | 补丁来源、SHA256、槽位选择依据、何时需重制 |
| skill `marble-kernel-ci` | 操作流程：首次接入 / 版本更新 |