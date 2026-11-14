# AGENTS.md — Marble 内核 CI（Evolution X / KernelSU / Droidspaces）

> 面向将来接手本仓库的 agent。**先读这一份**，`droidspaces-AGENTS.md` 是最初的任务书（历史归档，部分内容已被本文件取代）。
> 机器可验证的事实（pin、fragment、配置项）以 `config/*.json` 和 `docs/versions.md` 为准；本文解释**为什么**。

---

## 1. 目标与边界

用 GitHub Actions 为 **Redmi Note 12 Turbo / Poco F5（marble）** 编译 Evolution X 的内核，
产出 AnyKernel3 刷机包 + Draft Release。**Fedora 主机只做仓库维护、静态检查、触发 CI、看日志、审计产物。**

| 做 | 不做 |
|---|---|
| 改配置/脚本/workflow，跑本地静态门禁，dispatch Actions，下载审计 artifact | 在本地编译内核、建第二套构建系统、手搓刷机包 |
| 需要时用 `adb` **只读**采集设备信息 | 自动刷机、`fastboot flash`、改槽位/vbmeta、清数据 |

**只有用户明确授权才进刷机阶段。**

---

## 2. 硬事实基线（2026-11-16 真机实测，改动前先复核）

| 项 | 值 | 证据来源 |
|---|---|---|
| 设备 | `marble`（Redmi Note 12 Turbo / POCO `23049RAD8C`），slot `_a` | `adb shell getprop ro.product.device` |
| ROM | **Evolution X 12.4** = Android **17**，manifest 分支 **`cnb`** | `ro.evolution.build.version`、`Evolution-X/OTA@cnb/builds/marble.json` |
| 内核 | **5.10.269**，release `5.10.269-gki-g658b84f13496` | `adb shell uname -r` |
| 内核源码 | `Evolution-X-Devices/kernel_xiaomi_sm8450` @ **commit `658b84f13496fa94659905e5f29b31cfde41d0ce`**（分支 `cnb`） | `uname -r` 的 `-g` 后缀（`CONFIG_LOCALVERSION_AUTO=y`） |
| defconfig 链 | `gki_defconfig` + `vendor/{waipio_GKI,xiaomi_GKI,marble_GKI,debugfs}.config` | `device_xiaomi_sm8450-common@cnb` 的 `TARGET_KERNEL_CONFIG` + 真机 `/proc/config.gz` |
| 官方工具链 | AOSP clang **r563880c**（LLVM 21.0.0）；仓库默认 `llvm-22.1.8` | `cat /proc/version` |
| Root | **KernelSU**，pin tag **`v3.3.1`**（`0c0fdb96…`） | `config/managers.json` |
| 容器 | **Droidspaces** 开启；SUSFS **关闭** | `config/kernel-sources.json` 的 `source_patches.requires_env` |
| 真机 config 快照 | `reports/evidence/marble-12.4-stock-config.txt`（6249 项） | 设备 `/proc/config.gz`（**444 世界可读，不需要 root**） |

### 2.1 为什么内核 commit 必须钉死（本项目最容易踩的坑）

`CONFIG_LOCALVERSION_AUTO=y`，模块的 `vermagic` 里带完整 release 串（含 `-g<commit>`）。
换一个 commit 编出来的内核 → release 变成 `-g<别的sha>` → **vendor_boot / vendor_dlkm 里那 396 个模块全部拒载**
（表现为不开机/黑屏/无 WiFi），而 ZIP 本身"编译成功"。

所以：**不要用分支 HEAD 构建；用 `uname -r` 反推 commit 并写进 `config/evolution-x-versions.json`。**
resolver 里有一道守卫：`kernel_release_suffix` 末 12 位必须等于 `kernel_commit` 前缀，不一致直接报错。

---

## 3. 仓库结构（复用优先，别重写）

```
.github/workflows/
  build-matrix.yml   唯一用户入口（workflow_dispatch）；setup → build[*] → aggregate → release
  build-core.yml     workflow_call 实现：resolve → validate → checkout → toolchain → patch → build → package → audit
  preflight.yml      push/PR 的静态门（bash -n / shellcheck / actionlint / 全部 tests / whitespace）
config/
  evolution-x-versions.json  ★ ROM 版本 → 内核 commit/fragment/工具链 的唯一真源
  kernel-sources.json        preset（repo/ref/fragments/source_patches）
  managers.json              root manager 白名单（KernelSU 已 pin tag）
  marble.env                 工具链 URL/SHA、AnyKernel3 pin 等常量
  susfs-refs.json            SUSFS 版本 → commit（本轮未用）
scripts/
  resolve-kernel-source.sh   ★ 读 mapping，输出 SOURCE_REF=<commit> + SOURCE_REF_LABEL=<branch>
  derive-kernel-pin.sh       ★ 从 `uname -r` 反推内核 pin（升级 ROM 的第一条命令）
  validate-inputs.sh         组合合法性（Droidspaces 必须有 pin+profile+补丁序列；SUSFS 分支白名单）
  apply-kernel-source-patches.sh  preset 级补丁（requires_env 门控 + match_refs 接受 branch 或 commit）
  build-kernel.sh            defconfig/LTO/Droidspaces 配置 + 终态断言
  package-anykernel.sh       AnyKernel3 + ZIP 命名
  prepare-promoted-release.sh 校验 artifact → 写 release-metadata.env（tag/title 由此派生）
  write-build-info-json.sh   provenance（rom.* / kernel.* / droidspaces.* / config_sha256）
patches/kernel-sources/evolution-x/droidspaces/   Droidspaces GKI kABI 补丁（原样入库 + SHA256 + README）
tests/                     20 个策略/回归测试，preflight 全跑
reports/                   preflight-report.md（审查报告） + evidence/（真机 config 等）
```

设计约束：builder job 只读（`contents: read`），写权限只在 release job；Actions 全部按 commit SHA 钉住；
脚本承载逻辑、workflow 只编排；**不要新增第二套构建 workflow**（`tests/test-workflow-policy.sh` 会拦）。

---

## 4. 默认构建形态

```
Source  : evolution-x（默认勾选）        Manager : KernelSU（默认勾选）
Droidspaces : 开                        SUSFS   : 关
Toolchain : auto → llvm-22.1.8          LTO     : thin（不要 none：会连带关掉 CFI_CLANG）
Scope : image-only                      Release : create_draft_release 默认开
```

触发（等价于 UI 上点 Run）：

```bash
gh workflow run build-matrix.yml \
  -f build_source_melt=false -f build_source_evolution_x=true \
  -f build_none=false -f build_kernelsu=true \
  -f enable_droidspaces=true -f enable_susfs=false \
  -f evolution_x_version=12.4 -f toolchain=auto -f lto=thin \
  -f build_scope=image-only -f enable_ccache=true \
  -f create_draft_release=true
```

产物：`AK3_marble_LOS_evolution-x_kernelsu-v3.3.1-code32680_rN.zip`；
Draft tag `marble-evolution-x-12.4-droidspaces-rN`，title `Evolution-X 12.4 · kernelsu · Droidspaces · rN`。

---

## 5. 版本更新 SOP（三种更新的区别）

### 5.1 Evolution X 升级（例：12.4 → 12.5）——**唯一"要干活"的一种**

内核可能换 commit，甚至换大版本（5.10 → 6.6）。**按顺序做，别跳步。**

1. **升级 ROM 后先进系统**，采集四样东西：

   ```bash
   adb shell 'getprop ro.evolution.build.version; getprop ro.build.version.release'
   adb shell uname -r
   adb shell 'zcat /proc/config.gz' > reports/evidence/evo-<ver>-stock-config.txt
   adb shell 'ls /vendor/lib/modules | wc -l'
   ```

2. **反推内核 pin**（40 位 commit 用 GitHub API 补全）：

   ```bash
   bash scripts/derive-kernel-pin.sh --adb --version 12.5
   ```

3. **确认分支与 fragment 链**（内核大版本可能变）：

   ```bash
   # 这个 commit 属于哪个分支？
   gh api repos/Evolution-X-Devices/kernel_xiaomi_sm8450/commits/<40位sha> --jq '.sha'
   gh api repos/Evolution-X-Devices/device_xiaomi_marble/contents/evolution.dependencies?ref=cnb --jq .content | base64 -d
   # 5.10 走 device_xiaomi_sm8450-common@cnb 的 TARGET_KERNEL_CONFIG（4 个 fragment）
   # 6.6 走 device_xiaomi_sm8450-common@cnb-6.6（无 TARGET_KERNEL_CONFIG，Kleaf 用 vendor/waipio_perf.config）
   ```

4. **改 `config/evolution-x-versions.json`** 一个块：`kernel_commit` / `kernel_release_suffix` /
   `config_fragments` / `droidspaces_profile` / `susfs_kernel_branch` / `official_toolchain`；
   把 `default` 指向新版本。**这是唯一必须手工编辑的文件。**

5. **同步两处 ref 门控**：`config/kernel-sources.json` 的 `source_patches.match_refs` 加上新 commit（或保留分支名）。

6. **5.10 → 6.6 迁移时的额外动作**（只在换大版本时）：
   - Droidspaces 补丁要换：6.6 树上 `001…6_7_8.patch` 的 hunk#2 **打不上**（尾部上下文被 `#ifdef CONFIG_RV` 替换），需重制；
   - SUSFS 分支 `gki-android12-5.10` → `gki-android15-6.6`（本轮关闭 SUSFS，故不影响）；
   - `LOCALVERSION` 从 `-gki` 变 `-4k`，vermagic 完全不同 → 必须换 commit，不能复用旧内核。

7. **本地门禁** → commit → push → 先跑 **S1（`none` + 无 Droidspaces）** → 下载 artifact，
   把 `config.txt` 和真机 config 逐项 diff：除工具链版本号与 LTO thin/full 外**不应有差异**。
   S1 通过后再跑完整的 KernelSU + Droidspaces + Draft。

> **如果新版本内核 commit 与旧版完全相同**：不需要重建，直接复用旧 ZIP（但要确认 config 与补丁一致）。

### 5.2 KernelSU 升级——**改一行 `default_ref`**

1. 看新 tag：`gh api repos/tiann/KernelSU/tags --jq '.[0:3][] | "\(.name) \(.commit.sha)"'`
2. 改 `config/managers.json` → `kernelsu.default_ref`，`notes` 里的 commit 一并更新；
   `docs/versions.md` 的 KernelSU 行同步。
3. `bash tests/test-*.sh`（`test-manager-policy.sh` 会校验 allowlist）→ push → dispatch。
4. 预期副作用：ccache key 含 `manager_commit` → **这一次会冷启动（约 20 分钟）**，之后恢复 11 分钟左右。
5. ZIP 名会自动带上新版本与 version code（`kernelsu-v3.3.1-code32680`），无需改命名逻辑。

### 5.3 Droidspaces 升级——**多数情况什么都不用做**

- 只是 App/CLI（APK）更新 → **内核不用动**，不用重建。
- 上游内核补丁变了（`ravindu644/Droidspaces-OSS` 的 `Documentation/resources/kernel-patches/`）才需要：
  1. 下载新补丁 → 替换 `patches/kernel-sources/evolution-x/droidspaces/` 下同名文件；
  2. **先验证**：`git apply --check`（严格，无 fuzz）在 pin 的 commit 上干净通过；
  3. 更新该目录 `README.md` 的 SHA256 表格；
  4. 更新 `tests/test-droidspaces-config.sh` 里写死的两个 sha256（否则测试会红）；
  5. 本地测试 → push → dispatch。

### 5.4 例行体检（每 2–4 周，或 CI 变慢/失败时）

| 检查 | 命令 |
|---|---|
| KernelSU / SUSFS / Droidspaces 是否有新版本 | `gh release list -R tiann/KernelSU` / `git ls-remote --heads https://gitlab.com/simonpunk/susfs4ksu.git` |
| upstream 是否已修了我们的源码级补丁 | `/workspace` 无关；看 `patches/kernel-sources/**/README.md` 的"何时应移除"说明 |
| ccache 命中率是否下降 | 看 artifact 的 `ccache-stats.txt` / summary 的 Cache 段 |
| 缓存体积 | GitHub → Actions → Caches |

---

## 6. 排错手册（含本项目真实踩过的坑）

| 症状 | 根因 | 处理 |
|---|---|---|
| `release/resolved-refs.env: line N: <tag>: command not found` | `resolve-refs.sh` 的 tag 解析用裸 `print`，`sub()` 改 `$2` 会重建 `$0` → 值变成 `<sha> <tag>`，被 source 时把 tag 当命令 | 两个 awk 分支必须 `print $2`；已有静态回归断言 |
| `release-metadata.env: line N: 12.4: command not found` | 环境文件里写了带空格的值（title），`source` 时被拆成命令 | 一律 `printf %q` 写；测试里真的 `source` 一遍并回读 |
| `Setup swap for LTO` → `fallocate: No space left on device`（但 `df /` 显示 88 GiB 空闲） | runner 的 `/mnt` 是独立小盘；第三方 action 写死 16 GiB 且固定落 `/mnt` | 已改为探测 `/mnt` 与 `/`、按可用空间收缩、`fallocate` 失败回落 `dd`、最终失败只告警 |
| `Missing config fragment` | fragment 列表与内核树不匹配（5.10 四件套 vs 6.6 的 `waipio_perf.config`） | 按 §5.1 第 3 步查 `TARGET_KERNEL_CONFIG` |
| `Droidspaces requires CONFIG_x=y` | 配置块没生效（Kconfig 依赖不满足，如 `IPC_NS` 需要 `SYSVIPC`/`POSIX_MQUEUE`） | 看 `out/.config`；`IPC_NS` 只有在前两者之后才出现 |
| `CONFIG_CFS_BANDWIDTH must stay disabled` | 有人开了 CPU/PID 限制 | 别开：会改 sched/cgroup 结构，数千符号 CRC 变化，vendor 模块拒载 |
| 构建成功但不开机 / vendor 模块拒载 | commit 漂移导致 vermagic 变化，或 fragment 链不对 | 用 `derive-kernel-pin.sh` 重钉；S1 的 config diff 会暴露 |
| `gh release create` 报 tag 已存在 | 同一 run number 重复使用 | 换一次新 run（run number 自增），或确认旧 draft 是否该删 |
| ARM64 编译报 armv9 相关错误 | 用了 `android-r416183b`（clang 12） | 用 `llvm-22.1.8`（`toolchain=auto` 已保证） |

更多历史记录：`docs/verification/*.md`、`reports/preflight-report.md`。

---

## 7. 安全与边界（硬规则）

- **不自动刷机**，不 `fastboot flash` / `adb shell dd` 写分区，不改活动槽 / vbmeta / 清数据。
- 刷机前必须有 `boot`/`vendor_boot`/`dtbo` 备份（用户已持有全分区镜像）。
- `sudo` 需密码，**禁止**把密码写进命令行/脚本/对话。需要 root 的写操作 → 写成脚本让用户自己跑。
- 删除/覆盖已发布 Release 需用户同意；**Draft** 可以按需清理，但先说一声。
- 密钥/API key 明文存本地配置（权限 600）是预期设计，不要贴进聊天、不要改成加密。
- 修改后必须：`bash tests/test-*.sh` + `shellcheck` + `actionlint` + `git diff --check` 全绿，再看 `git diff`。

---

## 8. 本地门禁（等价于 preflight.yml）

```bash
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 scripts/*.sh scripts/lib/*.sh tests/*.sh
actionlint
bash tests/test-*.sh
git diff --check
```

一次性装齐依赖：`bash scripts/dev-install-preflight-deps.sh`（`patch` / `ShellCheck` 走 dnf；
`actionlint` 1.7.12 放 `~/.local/bin`，与 CI 版本一致）。

注意：`tests/test-toolchain-auto.sh` 之类会写 `release/` 的测试已在临时目录运行；
若手工跑单个测试后仓库根出现 `release/`，先 `rm -rf release` 再跑全套（历史上有过顺序敏感缺陷）。

---

## 9. 验收清单（不要只看 CI 绿灯）

| 阶段 | 判定 |
|---|---|
| CI 构建 | 全 job 绿 + ZIP 审计 27 条目 + `Image` 为 `ARM64 boot executable` |
| 配置正确性 | CI 的 `config.txt` 与真机 config diff 只剩「工具链版本 + LTO thin/full」+ 我们主动开的项 |
| 产物审计 | `build-info.json` 里 rom/kernel/droidspaces 字段齐全；`zip_sha256` 与 `.sha256` 一致 |
| Draft Release | tag/title 含 ROM 版本 + Droidspaces；notes 无 Cache 段 |
| 设备验证 | `uname -r` == 目标 release；`dmesg` 无 `disagrees about version`/`Unknown symbol`；KernelSU Manager 显示 working；Droidspaces Requirements 全绿 |

**CI 成功 ≠ 内核通过验证**：只有刷机跑通才算（AGENTS 原任务书 §15）。

---

## 10. 当前状态与未验证项

已完成：内核映射钉死、KernelSU 集成、Droidspaces 补丁与配置、Release 身份修正、S1/r6 两次 CI 全绿、
Draft `marble-evolution-x-12.4-droidspaces-r6`。

未验证（需刷机）：

- `llvm-22.1.8` 编出的内核在真机上是否被 vendor 模块接受（理论 vermagic 一致，但 kABI 只能实测）；
- Droidspaces 容器实际能不能起来；
- KernelSU Manager 与内核 v3.3.1 的配合。

备选方案（若编译/开机异常）：官方内核实际用 **clang r563880c**，可新增工具链 preset ——
分支 `temp-android16-plus`，sparse path `clang-r563880c`，需在 `marble.env` 加 URL/分支/commit，
并在 `build-core.yml` 的 cache key 与 select 步骤加一个分支。

---

## 11. 文档索引

| 文件 | 内容 |
|---|---|
| `README.md` | 用户向：输入表、默认值、ZIP 命名、Draft Release |
| `docs/versions.md` | 所有 pin（含 12.4 内核 commit、KernelSU tag、工具链）与 vermagic 说明 |
| `docs/ARCHITECTURE.md` | 分层/管线/缓存设计 |
| `reports/preflight-report.md` | 本轮完整审查 + Phase 2/3 记录（含 CI 事故复盘） |
| `reports/evidence/marble-12.4-stock-config.txt` | 真机内核配置原件（config diff 的基准） |
| `patches/kernel-sources/evolution-x/droidspaces/README.md` | 补丁来源、SHA256、为何选 6/7/8 槽位、何时需重制 |
| `droidspaces-AGENTS.md` | 最初的任务书（历史归档） |