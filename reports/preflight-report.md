# Preflight Report — Marble × Evolution X 12.4 × KernelSU × Droidspaces

- 审查日期：2026-11-16（本机时间），**当日晚间用真机复测并修订**
- 审查对象：`/home/thdbd/Projects/marble-kernel-builder`（fork `wzk0/marble-kernel-builder`，上游 `mohdakil2426/marble-kernel-builder`）
- 阶段：Phase 1 — Preflight（只读审查 + 只读 `adb` 取证）
- 本轮**未**执行：修改任何构建代码、触发 Actions、刷机/写入设备、内核编译、创建/删除 Release
- 设备证据：`reports/evidence/marble-12.4-stock-config.txt`（真机 `/proc/config.gz` 导出，6249 项）

> **修订说明（重要）**：第一版报告基于分支静态文件推断"12.4 = Android 17 + 内核 6.6"，**该推断错误**。
> 真机实测证明 **12.4 = Android 17 + 内核 5.10.269**，且现有 `evolution-x` preset 的 repo/ref/fragment **都是对的**。
> 6.6 属于 12.5+ 的未来状态（分支在 11/13–14 才迁移）。§3 已整节重写，§5 改为真机源码 + 真机 config 实测结论。

---

## 0. 结论摘要

| 结论 | 状态 |
|---|---|
| 仓库可直接复用 | ✅ 是。构建/打包/审计/缓存/摘要/Draft Release 链路完整，已有 CI 验证记录 |
| Evolution X 12.4 的真实内核 | ✅ **已确定**：Android 17 + **5.10.269**，commit `658b84f13496fa94659905e5f29b31cfde41d0ce`（真机 `uname -r` 反推） |
| 现有 `evolution-x` preset 是否需要改 | ✅ **不需要**（repo/ref/fragments 全部与真机 `.config` 吻合）。需要补的是"按 commit pin"这一层 |
| 现有 gki_fragments 是否可用 | ✅ 可用（`gki_defconfig + waipio_GKI + xiaomi_GKI + marble_GKI + debugfs`，已由真机 config 验证） |
| 官方 toolchain | AOSP clang **r563880c**（LLVM 21.0.0）；仓库现有 `llvm-22.1.8` 是"接近但不等同"的选项 |
| BakaSU 是否已支持 | ❌ 否；但用户已决定换 **KernelSU**，而 KernelSU 在 builder 里是 **0 改动**（见 §4.5） |
| Droidspaces kABI 补丁是否可直接套用 | ✅ **可以**。`001…6_7_8` 与 `002…posix_mqueue` 在真机同源 5.10 树上 `git apply --check` **严格通过** |
| Droidspaces 必需配置缺口 | 5 项必开（SYSVIPC / POSIX_MQUEUE / IPC_NS / PID_NS / DEVTMPFS）+ 1 项网络（XT_MATCH_ADDRTYPE），见 §5.3 |
| SUSFS 是否需要动 | ➖ 12.4 完全不用动：内核 5.10 ↔ `gki-android12-5.10` 正好对上；仅升级到 6.6 时才需参数化 |
| 缓存/Artifact/Draft Release 可否复用 | ✅ 可以，但有 1 个真实缺陷（Draft Release 的 tag/title 取自 `kernel_source` 输入，默认 `auto`） |
| 完成"只改版本参数即可构建" | 需要 8~10 处改动（详见 §8），比第一版预估少 |

**最大风险（已修正）**：**vermagic 一致性**。真机 `CONFIG_LOCALVERSION_AUTO=y`，release 带 `-g<commit>`；
源码 commit 不等于 `658b84f…` 时，396 个 vendor 模块会全部因 vermagic 不匹配而拒载（表现为不开机/无显示/无 WiFi）。
第二位的风险是 Droidspaces 的 kABI 与 LTO/CFI 对齐（§5.4）。"5.10 vs 6.6 错配"这一条**不成立**。

---

## 1. 仓库真实状态

### 1.1 项目说明文件

| 检查项 | 结果 |
|---|---|
| 根目录 `AGENTS.md` | ❌ **不存在** |
| 现有说明文件 | `droidspaces-AGENTS.md`（20292 B，**未被 git 跟踪**，`?? droidspaces-AGENTS.md`） |
| 处置 | 本轮把它当作项目任务书使用。Phase 2 建议重命名为 `AGENTS.md` 并提交（需用户确认，本轮未动） |

### 1.2 Git

```
remote   origin  git@github.com:wzk0/marble-kernel-builder.git   （fork，parent = mohdakil2426/marble-kernel-builder）
branch   main  →  origin/main
HEAD     a2e7fee5ebbbea31919a2701a5f561d4fc6db5af
         Merge pull request #11 from mohdakil2426/refactor/cleanup-overengineering
worktree 干净，唯一未跟踪项：?? droidspaces-AGENTS.md
stash    空
上游      与 origin/main 完全同步（pushed_at 2026-10-14）
```

### 1.3 结构

```
.github/workflows/{build-matrix.yml, build-core.yml, preflight.yml, weekly-melt-smoke.yml}
config/{marble.env, managers.json, kernel-sources.json, susfs-refs.json}
scripts/  18 个（含 lib/summary-common.sh）
tests/    18 个 test-*.sh
ak3/      anykernel.sh + banner（AnyKernel3 覆盖层）
patches/kernel-sources/pa-gr/vauxite/{series, 0001-...patch}
docs/     ARCHITECTURE.md、versions.md、manager-matrix.md、verification/*、previews/*
```

### 1.4 本轮本地静态检查结果（工具补齐后）

第一轮缺 `patch`/`shellcheck`/`actionlint`，无法复现 `preflight.yml`。补齐后（`patch` 2.8、`ShellCheck` 0.11.0、
`actionlint` 1.7.12 放在 `~/.local/bin`，辅助脚本 `scripts/dev-install-preflight-deps.sh`）：

```
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh          → OK
shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 …        → OK
actionlint                                                → OK
bash tests/test-*.sh                                      → 17/17 通过
git diff --check                                          → OK
```

**但补工具后暴露了一个真实的仓库缺陷**（此前被"缺 patch"掩盖）：

| 现象 | 根因 |
|---|---|
| 按非字母序跑测试时 `tests/test-package-naming.sh` 失败：期望 `AK3_marble_**MELT**_melt_…` 实得 `AK3_marble_**LOS**_melt_…` | ① `tests/test-toolchain-auto.sh` 与 `tests/test-workflow-policy.sh` 在仓库根目录**留下 `release/kernel-source.env`**（`ROM_FAMILY=los`/`PACKAGE_FAMILY=LOS`），测试不隔离；② `scripts/package-anykernel.sh:6` 捕获了 `_caller_pkg="${PACKAGE_FAMILY:-}"` 但**从未使用**，于是被 `source release/kernel-source.env` 里的残留值覆盖 |

影响面：CI 里 `bash tests/test-*.sh` 是字母序（`package-naming` 先于 `toolchain-auto`），所以**CI 一直是绿的**；
但只要残留文件存在（本地手工跑、或以后调整测试顺序），打包就会**静默生成族名错误的 ZIP**。属于低危但必须修的脏点。

---

## 2. 当前架构（复用面）

### 2.1 控制流

```
build-matrix.yml (workflow_dispatch，唯一正式入口)
  ├─ setup              → 5 个快测 + scripts/generate-build-matrix.sh → matrix JSON
  ├─ build[*]           → build-core.yml (workflow_call)，每个矩阵项一个 job
  │                        resolve-kernel-source → resolve-toolchain → validate-inputs
  │                        → checkout kernel → apply-kernel-source-patches
  │                        → toolchain cache/fetch → resolve-refs → ccache/ThinLTO restore
  │                        → patch-manager → read-manager-version → apply-susfs
  │                        → build-kernel → read-manager-build-metadata
  │                        → package-anykernel → build-info(.txt/.json) → audit
  │                        → summary → attest → upload artifact → cache save
  ├─ aggregate-summary  → generate-matrix-summary.sh（下载 marble-flash-*-r<run>）
  └─ release            → prepare-promoted-release.sh → gh release create --draft
```

### 2.2 数据流

```
config/*.json + marble.env
  → resolve-kernel-source.sh  ⇒ release/kernel-source.env + GITHUB_ENV/OUTPUT
  → resolve-refs.sh           ⇒ release/resolved-refs.env（精确 commit）
  → kernel-source/（临时工作树，永不回写上游）
  → kernel-source/release/{Image,*.zip,*.sha256,build-info.*,summary.md,zip-audit.txt}
  → artifact marble-flash-<label>-<scope>-r<run>
  → （可选）Draft Release
```

### 2.3 关键设计约束（改动时必须保持）

| 约束 | 位置 |
|---|---|
| 内核源码只读，补丁仅落在 runner 临时树 | `build-core.yml`、`patch-manager.sh`、`apply-susfs.sh` |
| builder job 只 `contents: read`，写权限只在 release job | `build-core.yml` / `build-matrix.yml` |
| 单一正式入口，禁止新增第二套构建工作流 | `tests/test-workflow-policy.sh` |
| ZIP 命名格式锁定 | `scripts/package-anykernel.sh` + `tests/test-package-naming.sh` |
| artifact 名必须匹配 `marble-flash-*-r<run>` 且以 `-(image-only\|full)-rN` 结尾 | `build-matrix.yml`、`prepare-promoted-release.sh:38` |
| 所有 Actions 按 commit SHA 固定 | `tests/test-workflow-policy.sh` |

---

## 3. Evolution X 12.4 → 真实 kernel source / branch / commit（**真机实测，2026-11-16**）

### 3.1 设备实测数据（`adb`，只读）

| 项 | 实测值 |
|---|---|
| 设备 | `marble` / POCO `23049RAD8C`（Redmi Note 12 Turbo），transport 正常 |
| ROM 标识 | `ro.evolution.build.version = EvolutionX-17.0-20261112-marble-12.4-Official`；`ro.modversion = 12.4`；`ro.evolution.display.version = v12.4-20261112` |
| Android | `ro.build.version.release = 17`，`sdk = 37`，`ro.build.display.id = CP2A.260605.016` |
| 构建时间 | `ro.build.date.utc = 1794505894` → **2026-11-12 17:51:34 UTC**（与 OTA json 的 `timestamp` 完全一致） |
| 指纹 | `generic/marble/marble:17/CP2A.260605.016/eng.androi:user/release-keys`（vendor 指纹继承 HyperOS `OS3.0.4.0.VMRMIXM`） |
| **内核** | `Linux version 5.10.269-gki-g658b84f13496 (build-user@build-host) … clang version 21.0.0 (r563880c) … #1 SMP PREEMPT Thu Nov 12 17:59:07 UTC 2026` |
| 内核编译时间 | 2026-11-12 17:59:07 UTC，比 ROM 打包时间晚 8 分钟 → **确证该内核就是这套 ROM 的官方产物**，非第三方刷入 |
| `/proc/config.gz` | **可读**（mode 444，46170 B）→ 已导出至 `reports/evidence/marble-12.4-stock-config.txt`（6249 项） |
| Root 状态 | 无 root（`su: inaccessible or not found`），`/sys/module` 无 `kernelsu`/`susfs`，`getprop` 无 ksu 属性 |
| 已装 Manager | `me.weishu.kernelsu`（官方 KernelSU）+ `com.resukisu.resukisu`（旧 ReSukiSU，残留）→ **均未激活**（内核无 KSU） |
| 槽位 / vbmeta | `ro.boot.slot_suffix = _a`，`verifiedbootstate = green`，`vbmeta.device_state = locked`（疑似 ROM 的 PIF 伪造，不作 AVB 判断依据） |
| vendor 模块 | `/vendor/lib/modules` 与 `/vendor_dlkm/lib/modules` 各 **396** 个 `.ko` |

### 3.2 结论：**12.4 用的是 5.10，不是 6.6**（修正 P0 轮的静态推断）

我在第一版报告里根据 `device_xiaomi_marble@cnb` 的 `evolution.dependencies`（指向 `cnb-6.6`）推断"12.4 = 6.6 GKI"是**错的**。
那份依赖清单在 **2026-11-13/14** 被改成 6.6，而 12.4 是 **2026-11-12** 构建的。真机内核字符串 `g658b84f13496` 直接对应
`Evolution-X-Devices/kernel_xiaomi_sm8450@**cnb**`（5.10.269）的 HEAD，与该分支的 5.10 事实完全吻合。

### 3.3 12.4 的精确映射（可直接 pin，无需猜测）

| 项 | 值 | 证据来源 |
|---|---|---|
| manifest 分支 | `cnb`（Android 17，AOSP `android-17.0.0_r1`） | `Evolution-X/manifest@cnb/default.xml` + `ro.build.version.release=17` |
| ROM 文件名 | `EvolutionX-17.0-20261112-marble-12.4-Official.zip` | `Evolution-X/OTA@cnb/builds/marble.json` + 真机属性 |
| **kernel repo** | `Evolution-X-Devices/kernel_xiaomi_sm8450` | 内核 release string 的 `-gki-` 前缀 + 该树 `Makefile` = 5.10.269 |
| **kernel ref** | `cnb` | 同源；分支 HEAD 即真机 commit |
| **kernel commit** | `658b84f13496fa94659905e5f29b31cfde41d0ce` | 真机 `uname -r` 的 `g658b84f13496`（git 短 SHA 由 `CONFIG_LOCALVERSION_AUTO=y` 注入） |
| 内核版本 | 5.10.269（GKI android12-5.10） | `/proc/version` |
| **官方 toolchain** | AOSP clang **r563880c**（LLVM 21.0.0，PGO/BOLT/LTO/MLGO） | `/proc/version` |
| **defconfig 链** | `gki_defconfig` + `vendor/waipio_GKI.config` + `vendor/xiaomi_GKI.config` + `vendor/marble_GKI.config` + `vendor/debugfs.config` | `device_xiaomi_sm8450-common@cnb` 的 `TARGET_KERNEL_CONFIG`（第 79–84 行）+ 真机 `.config` 交叉验证 |
| LTO / CFI | `CONFIG_LTO_CLANG=y` + `CONFIG_LTO_CLANG_FULL=y`，`CONFIG_CFI_CLANG=y`（+ `CFI_CLANG_SHADOW=y`） | 真机 `.config` |
| LOCALVERSION | `CONFIG_LOCALVERSION="-gki"` + `CONFIG_LOCALVERSION_AUTO=y` | 真机 `.config` |
| SUSFS 分支 | **`gki-android12-5.10`** —— 与仓库现有配置**完全一致** | 内核 5.10 + `git ls-remote` 实测该分支存在 |
| 分区/引导 | `BOARD_BOOT_HEADER_VERSION := 4`，`BOARD_INCLUDE_DTB_IN_BOOTIMG := true`，`BOARD_USES_GENERIC_KERNEL_IMAGE := true`，vendor_boot 内含 dlkm 模块 | `device_xiaomi_sm8450-common@cnb` |

`TARGET_KERNEL_CONFIG` 原文（`device_xiaomi_sm8450-common@cnb`）：

```make
TARGET_KERNEL_CONFIG := \
    gki_defconfig \
    vendor/waipio_GKI.config \
    vendor/xiaomi_GKI.config \
    vendor/$(PRODUCT_DEVICE)_GKI.config \
    vendor/debugfs.config
```

→ **这就是 `config/kernel-sources.json` 里 `evolution-x` preset 的 fragment 列表**。`vendor/debugfs.config` 的内容是
`CONFIG_DEBUG_FS=n / CMA_DEBUGFS=n / PAGE_OWNER=n / PAGE_PINNER=n`，与真机 `# CONFIG_DEBUG_FS is not set` 吻合。

### 3.4 关键后果：**vermagic 必须逐字节一致 → commit 必须钉死**

真机 `CONFIG_LOCALVERSION_AUTO=y`，内核 release = `5.10.269-gki-g658b84f13496`。
模块的 `vermagic` 字符串包含完整 `UTS_RELEASE`，因此：

- **用同一个 commit（`658b84f…`）构建 → vermagic 相同 → 396 个 vendor 模块可正常加载**。
- 用分支更新后的 HEAD（不同 commit）构建 → release 变成 `…-g<别的 sha>` → **所有 vendor 模块 vermagic 不匹配、全部拒载**，表现为无法开机/无显示/无 WiFi。

所以"只改一个版本参数"的正确实现是：**版本号 → 内核 release 字符串 → 精确 commit**，而不是"用分支 HEAD"。
而且这个映射可以**从手机直接读出来**：`adb shell uname -r` 的 `-g` 后缀就是 commit 前缀（40 位可通过 GitHub API 补齐）。
这条规则对以后每一个 ROM 版本都适用，且不需要任何人工调查。

### 3.5 现有 `evolution-x` preset 是否需要改

| 字段 | 现值 | 12.4 是否需要改 |
|---|---|---|
| `repo` | `Evolution-X-Devices/kernel_xiaomi_sm8450` | ❌ 不用改 |
| `default_ref` | `cnb` | ❌ 不用改（**但必须改为按 commit pin，见 §3.4**） |
| `config_fragments` | waipio/xiaomi/marble/debugfs | ❌ 不用改（已由真机 config 验证） |
| `base_defconfig` | `gki_defconfig` | ❌ 不用改 |
| `defconfig_mode` | `gki_fragments` | ❌ 不用改 |
| `recommended_toolchain` | `llvm-22.1.8` | ⚠️ 可保留，但官方用的是 **r563880c**；见 §11 风险 5 |

**结论：P0 报告里"5.10/6.6 错配"的最高风险项不成立——现有 preset 对 12.4 是对的。**真正必须补的是
"版本 → commit pin"这一层，以及 BakaSU→KernelSU、Droidspaces 配置。

### 3.6 12.5+ 的未来状态（记录备查，本轮不动）

分支已经向前走了，下次升级要重新按 §3.4 的规则从真机 `uname -r` 取 commit：

- `device_xiaomi_sm8450-common@cnb-6.6` 现 HEAD `7167e199`（2026-11-14），`TARGET_KERNEL_VERSION := 6.6`，走 Kleaf/bazel
- `kernel_xiaomi_sm8450@cnb-6.6` 现 HEAD `1db41da4`（2026-11-09），`Makefile` = **6.6.144**
- 6.6 树的 config 链会变成 `gki_defconfig + vendor/waipio_perf.config`（`build.config.msm.perf: build_defconfig_fragments()`），
  且 `vendor/waipio_GKI.config` / `vendor/debugfs.config` 在该树中**不存在**
- 6.6 用 `gki_defconfig` 的 `CONFIG_LOCALVERSION="-4k"`，SUSFS 需换 `gki-android15-6.6`
- Droidspaces 在 6.6 树上 `001…6_7_8` 的 hunk#2 **打不上**（实测），需重制

这些是 **12.5 才需要处理的事**，不要提前套到 12.4 上。

## 4. Root Manager：BakaSU 现状 / 为什么改用 KernelSU

> **决策已定（2026-11-16）**：改用**官方 KernelSU**，BakaSU 接入工作取消。
> 本节保留 BakaSU 的调查记录，供日后若确定要用 SUSFS 时复用。

### 4.1 结论：**完全不支持**

`config/managers.json` 只有 `none / kernelsu / kernelsu-next / sukisu-ultra / resukisu`。
逐层检查：

| 层 | 文件 | 现状 |
|---|---|---|
| 允许列表 | `config/managers.json` | 无 `bakasu` |
| 校验 | `scripts/validate-inputs.sh:16-19` | `case` 白名单缺 `bakasu` → 直接 `Unsupported manager` 退出 |
| 矩阵生成 | `scripts/generate-build-matrix.sh:43-49` | `manager_flags` 缺 `BUILD_BAKASU` |
| 工作流 UI | `build-matrix.yml:42-61` | 无 `build_bakasu` 复选框 |
| 引用解析 | `scripts/resolve-refs.sh` | 纯数据驱动（读 `managers.json`）→ 加 JSON 即可工作 |
| setup 调用 | `scripts/patch-manager.sh` | `curl raw.githubusercontent.com/<repo>/<commit>/<setup_path>` 后 `bash setup.sh <commit>` |
| 版本解析 | `scripts/read-manager-version.sh` | `KernelSU`/`KernelSU-Next`/… 候选目录；BakaSU 克隆到 `KernelSU/` → **目录能命中** |
| 构建元数据 | `scripts/read-manager-build-metadata.sh` | awk 只认 `KernelSU/KernelSU-Next/SukiSU-Ultra/ReSukiSU` 行 → **匹配不到 BakaSU** |
| SUSFS 集成 | `scripts/apply-susfs.sh:45` | 候选 Kconfig 含 `KernelSU/kernel/Kconfig` → **能命中**；`^config KSU_SUSFS$` 在 BakaSU 中存在 ✓ |
| 打包 token | `scripts/package-anykernel.sh:40-47` | 无 `bakasu` → 落到 `sanitize_token`，仍可用但语义不明 |
| 摘要展示 | `scripts/lib/summary-common.sh:24-43` | `manager_display` / `manager_app_url` 无 `bakasu` |
| 策略测试 | `tests/test-manager-policy.sh:50-59` | **硬断言 allowlist 字典** → 加 manager 必须同步改测试 |

### 4.2 BakaSU 上游事实（已核对）

| 项 | 事实 |
|---|---|
| 仓库 | `Baka-SU/BakaSU`（public，2186★，default `main`，pushed 2026-11-13） |
| 渊源 | **Formerly known as ReSukiSU**，是 `tiann/KernelSU` 的 downstream |
| 安装脚本 | `kernel/setup.sh`（4353 B）存在，路径符合 `managers.json` 的 `setup_path` 约定 |
| setup.sh 行为 | `git clone https://github.com/Baka-SU/BakaSU KernelSU` → `git stash` → `git pull` → `git checkout <commit>` → `ln -sf` 到 `drivers/kernelsu` → 追加 `obj-$(CONFIG_KSU) += kernelsu/` 到 `drivers/Makefile` → 在 `drivers/Kconfig` 中 `source "drivers/kernelsu/Kconfig"` |
| Kconfig | `kernel/Kconfig` 有 `config KSU` 与 **`config KSU_SUSFS`**（"SUSFS Inline Hook"） |
| 版本 | `kernel/Kbuild`：`KSU_VERSION := 30000 + $(git rev-list --count HEAD) + 700`，编译日志打印 `-- BakaSU version code: N` / `-- BakaSU version name: …` |
| 稳定 tag | `v4.1.0` → `0d27e685cb9f1b873cd334371c0d8b6ea4c3aea9`；最新发布为预发布 `v4.2.0-rc3`（`239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb`） |
| KMI 支持 | 官方声明支持 GKI 2.0（kernel 5.10+）→ **6.6 在支持范围内**；`kernel/Makefile` 甚至已处理 `android17-6.18` |
| SUSFS | 本项目 SUSFS 只做「backport 到 4.3+」；`kernel/tools/susfs_compat.mk` 只做兼容检测，**不提供 fs/ 补丁** → 仍需 simonpunk 内核补丁（与现有 `apply-susfs.sh` 思路一致） |

### 4.3 接入所需的具体修改（最小可用集）

1. `config/managers.json` 增加：

```json
"bakasu": {
  "display": "BakaSU",
  "repo": "Baka-SU/BakaSU",
  "default_ref": "v4.1.0",
  "setup_path": "kernel/setup.sh",
  "susfs_ref": "",
  "status": "stable",
  "notes": "BakaSU (formerly ReSukiSU). SUSFS blocked in v1: kernel-side SUSFS patches are not part of the manager repo."
}
```

2. `scripts/validate-inputs.sh`：`case` 白名单加 `bakasu`；`ENABLE_SUSFS=true && MANAGER=bakasu` → 显式拒绝（避免落进 `case` 空分支静默放过）。
3. `scripts/generate-build-matrix.sh`：`manager_flags` 加 `("bakasu", os.environ.get("BUILD_BAKASU","false"))`。
4. `build-matrix.yml`：新增 `build_bakasu` 复选框 + 传给 `generate-build-matrix.sh` 的 `BUILD_BAKASU`。
5. `scripts/package-anykernel.sh`：`manager_token` 加 `bakasu) manager_token="bakasu" ;;`。
6. `scripts/lib/summary-common.sh`：`manager_display`→`BakaSU`；`manager_app_url`→`https://github.com/Baka-SU/BakaSU/releases`。
7. `scripts/read-manager-build-metadata.sh`：awk 增加
   `/-- BakaSU version code:[[:space:]]*[0-9]+/` 与 `/-- BakaSU version name:[[:space:]]*.+/` 分支。
8. `scripts/read-manager-version.sh`：`wild_base_for_manager` 增加 `bakasu)`（BASE 语义与上游不同，`30000 + commits + 700`）；建议**不再注入** Makefile，改为完全依赖日志解析，避免与 Kbuild 计算结果打架。
9. `tests/test-manager-policy.sh`：`expected` 字典加 `"bakasu": "Baka-SU/BakaSU"`，并加 `expect_validation_failure bakasu true` / `expect_validation_success bakasu false`。
10. `scripts/write-build-info-json.sh` / 摘要：`manager.build.version_code` 复用既有字段即可，无需改结构。

> 注意：**不能只加 JSON**。第 3、4、5、7、9 项缺一不可，否则要么选不出来、要么打包名/摘要/版本号是错的。

### 4.4 BakaSU 相关的工程约束（易踩坑）

| 约束 | 影响 |
|---|---|
| `setup.sh` 在 CI 内 `git clone` + `git pull` | 构建时需外网；commit 仍被 `git checkout <pinned>` 固定，可复现 |
| `kernel/Kbuild` 里 `LOCAL_GIT_EXISTS=0` → `$(error ...)` | 必须让 `KernelSU/` 是**真 git 仓库**（setup.sh 的 clone 满足），不能改成拷贝源码 |
| `kernel/Kbuild` 会对 shallow 仓库执行 `git fetch --unshallow` | setup.sh 是全量 clone，正常；若改成 `--depth=1` 会触发网络请求 |
| 版本号依赖 manager 仓库自身 git 历史 | `30000 + commits + 700`，随 pin 的 commit 固定；但与 `read-manager-version.sh` 的 Wild 公式（`10200/30000`）不同，不能混用 |

### 4.5 备选方案：改用官方 KernelSU（用户 2026-11-16 提出的问题）

**结论：若不需要 SUSFS，官方 KernelSU 是更省事、风险更低的路线——它在 builder 里已经是“原生支持”。**

| 维度 | 官方 KernelSU（`tiann/KernelSU`） | BakaSU（`Baka-SU/BakaSU`） |
|---|---|---|
| builder 现状 | ✅ **已在 allowlist**，`kernelsu` 可直接选 | ❌ 需新增（§4.3 的 10 处改动） |
| 代码改动量 | **0** | 10 处代码/配置 + 6 处测试 |
| CI 验证记录 | ✅ `docs/verification/official-manager-ci-2026-06-22.md`（run `27933596271`，5.10 线全链通过） | ❌ 无 |
| 版本日志格式 | `-- KernelSU version: N` → **现有 awk 已能解析** | `-- BakaSU version code: N` → 需新增规则 |
| 内核 KMI 支持 | 官方声明 GKI 2.0（5.10+），arm64/x86_64 | GKI 2.0（5.10+），arm64/armv7/x86_64；`kernel/Makefile` 连 `android17-6.18` 都写了 |
| SUSFS | ❌ 官方 ref 无 SUSFS，builder **硬拒绝** | ⚠️ 有 `KSU_SUSFS`（inline hook），但内核侧仍需 simonpunk 补丁；且 6.6 分支需 `gki-android15-6.6` |
| 上游活跃度 | 20,556★，最后 push 2026-11-14，最新 tag `v3.3.1` | 2,186★，最后 push 2026-11-13，最新稳定 `v4.1.0`，`v4.2.0-rc3` 为预发布 |
| 与 BakaSU 的关系 | — | BakaSU **前身就是 ReSukiSU**，是 KernelSU 的下游 fork，内核侵入方式几乎一样 |
| 设备侧代价 | 需卸 BakaSU → 装 KernelSU Manager；现有授权/模块需重做（同为 metamodule 体系，格式兼容） | 保持现状 |
| 内核侧未知量 | 与 BakaSU **完全相同**（真正的风险是 commit/vermagic 与 kABI，与 manager 无关） | 同左 |

取舍建议：

- **选 KernelSU（已采纳）**：Phase 2 删掉 BakaSU 那 10 处改动，只保留“版本映射 + Droidspaces + Release 修复”；风险最小。设备上已装 `me.weishu.kernelsu`。
- **保留 BakaSU**：多花 10 处改动，换来内置 SUSFS 管理界面 + 多管理器支持（如果以后要用 SUSFS，迟早要走这条路）。
- **两者都不影响** 6.6 内核本身的可编译性/ABI 风险——那是内核构建路径问题，跟 root 方案无关。
- 注意：官方 KernelSU README 有 CAUTION——“近期内核有 breaking change，会导致 KernelSU 失效并可能在 **x86_64** 上 panic”。arm64 上无此告警，但 S3 阶段需实际验证开机与 `su`。
- 若以后确实要 SUSFS：BakaSU/ReSukiSU 路线随时可补，届时只需补 manager 接入 + `gki-android15-6.6` 分支参数化，工作可延后。

---

## 5. Droidspaces GKI kABI 补丁兼容性（**真机源码 + 真机 config 实测**）

### 5.1 上游真实位置（AGENTS.md 给的 URL 已失效）

`Droidspaces/Droidspaces` 不存在（404）。真实仓库：**`ravindu644/Droidspaces-OSS`**（org `Droidspaces` 只放周边工具）。

```
Documentation/resources/kernel-patches/GKI/below-kernel-6.12/
  001.GKI-below-6.12-fix_sysvipc_kabi_1_2_3.patch
  001.GKI-below-6.12-fix_sysvipc_kabi_3_4_5.patch
  001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
  002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch
Documentation/resources/kernel-patches/GKI/kernel-6.12/001.GKI-6.12-or-above-fix_sysvipc_kabi.patch
```

官方文档 `Documentation/Kernel-Configuration.md` 的规则：5.4–6.6 用 `below-kernel-6.12/`；**5.10 及更旧还要额外打 002**。

### 5.2 实测：在 12.4 的真实内核源码上，两个补丁都**干净通过**

对 `Evolution-X-Devices/kernel_xiaomi_sm8450@cnb`（5.10.269，即真机内核同源）做 `git apply --check`（严格模式，无 fuzz）：

| 补丁 | 结果 |
|---|---|
| `001…fix_sysvipc_kabi_1_2_3.patch` | ❌ 失败（`sched.h:1508`） |
| `001…fix_sysvipc_kabi_3_4_5.patch` | ❌ 失败（`sched.h:1510`） |
| **`001…fix_sysvipc_kabi_6_7_8.patch`** | ✅ **通过** |
| **`002.5.10_or_lower_…posix_mqueue.patch`** | ✅ **通过** |

原因（该树 `include/linux/sched.h`）：

```
1387: ANDROID_OEM_DATA_ARRAY(1, 32);
1390: ANDROID_KABI_USE(1, void *pf_io_worker);      ← 槽 1 已被 Android 占用
1392: ANDROID_KABI_USE(2, struct { … });           ← 槽 2 已被占用
1397-1402: ANDROID_KABI_RESERVE(3) … (8)          ← 3–8 空闲
974-975: struct sysv_sem sysvsem; struct sysv_shm sysvshm;   ← 包在 #ifdef CONFIG_SYSVIPC
```

槽 6/7/8 空闲、上下文完全匹配，所以 `6_7_8` 变体是正确选择（另两个变体引用 1/2/3 与 3/4/5，上下文与已被占用的槽位不符）。
`include/linux/sched/user.h:26` 的 `mq_bytes` 与 `ANDROID_KABI_RESERVE(1)(2)` 也匹配 `002`。

> 与 6.6 树形成对比：6.6 树上 `6_7_8` 的 hunk#2 打不上（尾部上下文被换成了 `#ifdef CONFIG_RV`）。**12.4 无此问题，无需重制补丁。**

### 5.3 真机 `.config` 的缺口表（`reports/evidence/marble-12.4-stock-config.txt`，6249 项）

**必须打开（当前缺失）**

| 配置项 | 真机现状 | 说明 |
|---|---|---|
| `CONFIG_SYSVIPC` | `n` | 需要 001 补丁保护 kABI |
| `CONFIG_POSIX_MQUEUE` | `n` | 5.10 需要 002 补丁 |
| `CONFIG_IPC_NS` | `<不存在>` | 依赖 `SYSVIPC \|\| POSIX_MQUEUE`，两者开后才会出现 |
| `CONFIG_PID_NS` | `n` | 官方 GKI 默认关；容器必需 |
| `CONFIG_DEVTMPFS` | `n` | 官方 5.10 GKI 关闭；容器硬件访问必需 |
| `CONFIG_NETFILTER_XT_MATCH_ADDRTYPE` | `n` | NAT 模式需要 |

**已经满足（无需动）**

```
CONFIG_NAMESPACES=y  CONFIG_UTS_NS=y  CONFIG_NET_NS=y
CONFIG_SECCOMP=y  CONFIG_SECCOMP_FILTER=y  CONFIG_SYSCTL=y
CONFIG_CGROUPS=y  CONFIG_MEMCG=y  CONFIG_CGROUP_FREEZER=y  CONFIG_CGROUP_NET_PRIO=y
CONFIG_BLK_DEV_LOOP=y  CONFIG_EXT4_FS=y  CONFIG_FUSE_FS=y  CONFIG_OVERLAY_FS=y
CONFIG_TUN=y  CONFIG_VETH=y  CONFIG_BRIDGE=y  CONFIG_NETFILTER=y  CONFIG_IP_NF_IPTABLES=y  CONFIG_NF_NAT=y
CONFIG_MODVERSIONS=y  CONFIG_CFI_CLANG=y  CONFIG_LTO_CLANG_FULL=y
```

**保持关闭（kABI 会被破坏，官方文档明令禁止）**

```
CONFIG_CFS_BANDWIDTH   → 真机当前 n   ✅ 保持
CONFIG_CGROUP_PIDS     → 真机当前 n   ✅ 保持
```

**可选（默认不开，按需评估）**

`USER_NS`(n) / `MACVLAN`(n) / `IP6_NF_NAT`(n) / `IP6_NF_TARGET_MASQUERADE`(不存在) / `TMPFS_XATTR`(n) / `TMPFS_POSIX_ACL`(n) /
`IP6_NF_TARGET_REJECT`(y) / `IP_NF_TARGET_REJECT`(y) / `NETFILTER_XT_MATCH_RECENT`(n) / `IP_SET`(n)

> 另注：`CONFIG_CGROUP_DEVICE=n`、`CONFIG_NF_TABLES=n` 出现在官方**非 GKI**清单里，GKI 清单未要求，且动 cgroup 结构有 kABI 风险 → **本轮不动**。

### 5.4 三个真实 kABI 风险点（按严重度）

| # | 风险 | 说明 | 处置 |
|---|---|---|---|
| 1 | **vermagic 不一致** | `CONFIG_LOCALVERSION_AUTO=y` → release 带 `-g<commit>`。commit 一变，396 个 vendor 模块全部拒载 | 源码 commit **必须**钉在 `658b84f13496fa94659905e5f29b31cfde41d0ce`（§3.4） |
| 2 | `CFS_BANDWIDTH` / `CGROUP_PIDS` | 会改调度器/cgroup 结构 → 数千导出符号 CRC 变化，无 padding 可救 | 显式禁止，并在 `build-kernel.sh` 里加断言 |
| 3 | LTO 模式不一致 | 官方是 `LTO_CLANG_FULL`；若我们选 `lto=none`，`olddefconfig` 会连带关掉 `CFI_CLANG`（依赖 LTO），偏离官方 | 默认 `lto=thin`（保留 CFI）；若要完全对齐可试 `full`（免费 runner 内存风险） |

补丁本身已被官方设计为只占用 KABI padding，结构**总大小与偏移不变**；剩余风险只能靠真机加载 vendor 模块验证。

### 5.5 落地方式（复用现有机制，不新增脚本）

```
patches/kernel-sources/evolution-x/658b84f/            ← 以 commit 短 SHA 命名，ref 变化即失效
  series
  0001-droidspaces-gki-sysvipc-kabi-6-7-8.patch        ← 上游原样（实测可直接应用）
  0002-droidspaces-gki-posix-mqueue-5.10.patch         ← 上游原样
```

`scripts/apply-kernel-source-patches.sh` 已支持 preset + `match_refs` 门控 + 失败硬退出，**无需修改脚本**，只需在
`config/kernel-sources.json` 的 `evolution-x` 里加 `source_patches` 块并把 `match_refs` 设成该 commit。
配置开关由 `build-kernel.sh` 负责（新增 `enable_droidspaces` 输入），并断言最终 `out/.config`。

## 6. 缓存 / 构建摘要 / Artifact / Draft Release 复用性

### 6.1 可以直接复用

| 能力 | 位置 | 复用结论 |
|---|---|---|
| Toolchain 缓存（Android clang） | `build-core.yml:166-207`，key `marble-builder-clang-v3-…-clang-r416183b-6e3223f` | ✅ 与内核版本无关，直接命中 |
| Toolchain 缓存（LLVM 22.1.8） | `build-core.yml:209-235`，SHA256 校验 | ✅ 直接复用 |
| ccache（v4 多级 restore-keys） | `build-core.yml:273-319` | ✅ 复用；但新 key 含 `kernel_source`+`source_commit`+`config_hash` → **6.6 首次必然冷启动**（`config_hash` 也会因新补丁/新 JSON 变化） |
| ThinLTO 缓存 | `build-core.yml:321-329, 439-444` | ✅ 复用；同样首跑冷 |
| 失败也保存对象缓存 | `always() && !cancelled() && cache-hit != 'true'` | ✅ 复用（对 6.6 首次构建很关键） |
| build-info.txt/json | `build-core.yml:349-390` + `write-build-info-json.sh` | ✅ 结构可扩展（加字段即可） |
| ZIP 审计 | `audit-flashable-zip.sh`（9 个必需条目 + 体积/类型检查） | ✅ 复用 |
| 摘要 | `generate-build-summary.sh` / `generate-matrix-summary.sh` / `lib/summary-common.sh` | ✅ 复用（需加 BakaSU/ROM 版本展示） |
| Artifact 上传 | `marble-flash-<label>-<scope>-r<run>`，30 天保留 | ✅ 复用 |
| Draft Release | `prepare-promoted-release.sh` + `gh release create --draft` | ✅ 逻辑可复用，**但见 6.2 缺陷** |

### 6.2 必须修的真实缺陷

1. **Draft Release 的 tag/title 取错源**
   `build-matrix.yml:273-284`：`source_slug="${KERNEL_SOURCE:-melt}"`，而 `KERNEL_SOURCE` 来自 `inputs.kernel_source`，其默认值是 **`auto`**。
   → 用复选框选 Evolution-X 时会生成 `marble-auto-r123` / 标题 `Marble Kernel · auto · r123`。
   修法：从 artifact 的 `build-info.txt`（`kernel_source=`）反推，或强制 release job 要求显式 `kernel_source`。

2. **SUSFS 内核分支写死**
   `build-matrix.yml:190` `susfs_kernel_branch: gki-android12-5.10`；
   `validate-inputs.sh:94-97` 只要不等于 `gki-android12-5.10` 就硬报错；
   `config/susfs-refs.json` 也只有该分支的 pin。
   → 6.6 的 SUSFS 分支应为 **`gki-android15-6.6`**（`git ls-remote` 实测存在，HEAD `ec03d0c73b821afa1d5037d6d493216f59744fcb`，且目录内确有 `50_add_susfs_in_gki-android15-6.6.patch`）。
   本轮不需启用 SUSFS，但**参数化必须做**，否则下一步（或任何换内核版本）都会被卡死。

3. **concurrency group 不含 `kernel_source`**
   `build-matrix.yml:121`。同时跑 Evolution-X 与 Melt 会互相排队（`cancel-in-progress: false`）。非阻塞，建议顺手加。

4. **`PACKAGE_FAMILY` 优先级失效 + 测试不隔离**（`scripts/package-anykernel.sh:6` + 两个测试）
   `_caller_pkg` 捕获后从未使用；`tests/test-toolchain-auto.sh`、`tests/test-workflow-policy.sh` 会在仓库根留下
   `release/kernel-source.env`。二者叠加会让打包族名（MELT/LOS）取自残留文件而不是本次调用 → ZIP 名错误。
   修法：`package-anykernel.sh` 恢复 `_caller_pkg` 优先级；两个测试改用 `mktemp -d` 或结束时清理 `release/`。

### 6.3 ZIP 命名的取舍

`package-anykernel.sh` 锁定了 `AK3_marble_<FAMILY>_<source>_<manager>[-version][-codeN][_susfs-vX.Y.Z]_rN.zip`，`test-package-naming.sh` 守它。
AGENTS.md §8.6 期望的 `marble-evolution-x-12.4-droidspaces-bakasu-rN` 形态**属于 Release 名/tag，不应改 ZIP 名**（改了要同步 4 个测试与 2 个脚本）。建议：
- ZIP 名保持现状（BakaSU 只需新增 `bakasu` token）；
- Release tag 改成 `marble-evolution-x-12.4-droidspaces-bakasu-rN`，标题用同串；
- ROM 版本写进 `build-info`（`evolution_x_version=`）+ 摘要表格。

---

## 7. 需要修改的文件（清单）

### 7.1 必改（Phase 2）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `config/evolution-x-versions.json`（新增） | 版本映射：`12.4 → android 17 / manifest cnb / kernel repo+ref+**commit `658b84f…`** / 5.10 fragment 列表 / droidspaces profile / toolchain / status` |
| 2 | `config/kernel-sources.json` | `evolution-x` **preset 本体不用改**（repo/ref/fragments 已被真机验证）；只加 `source_patches` 块指向 Droidspaces 补丁目录。**不要**改成 `cnb-6.6`（那是 12.5+） |
| 3 | `config/managers.json` | **不需要**（已决定用 KernelSU）。如日后改回 BakaSU 再看 §4.3 |
| 4 | `config/susfs-refs.json` | 12.4 **不需要**（5.10 ↔ `gki-android12-5.10` 已对）。升级 6.6 时再补 `gki-android15-6.6` |
| 5 | `config/marble.env` | 可选：`DROIDSPACES_PATCH_*` 常量；若要完全对齐官方内核，加 `AOSP_CLANG_R563880C_*`（见 §11 风险 5） |
| 6 | `scripts/resolve-kernel-source.sh` | 支持"按 ROM 版本覆盖 ref/**commit**/fragments/toolchain"（读映射文件）；`SOURCE_REF` 允许传 40 位 commit |
| 7 | `scripts/validate-inputs.sh` | `enable_droidspaces` 与 GKI/补丁序列的一致性校验；`evolution_x_version` 必须存在于映射文件；SUSFS 分支改为按内核版本推导（本轮可不做） |
| 8 | `scripts/generate-build-matrix.sh` | 透传 `evolution_x_version`（manager 部分**不改**，因为用 KernelSU） |
| 9 | `scripts/build-kernel.sh` | Droidspaces 配置块（SYSVIPC/POSIX_MQUEUE/IPC_NS/PID_NS/DEVTMPFS/XT_MATCH_ADDRTYPE）、`.config` 终态断言、显式禁止 `CFS_BANDWIDTH`/`CGROUP_PIDS`、保留 LTO（不得 `lto=none` 时丢 CFI 而不知情） |
| 10 | `scripts/read-manager-build-metadata.sh` | **不需要**（KernelSU 的 `-- KernelSU version: N` 已被现有 awk 覆盖，CI 已验证） |
| 11 | `scripts/read-manager-version.sh` | **不需要**（同上，现有逻辑对 `tiann/KernelSU` 有效） |
| 12 | `scripts/package-anykernel.sh` | banner 增加 ROM 版本/内核 release 行（可选）；manager token 不用改 |
| 13 | `scripts/lib/summary-common.sh` | **不需要**（`kernelsu` 已有显示名与链接） |
| 14 | `scripts/write-build-info-json.sh` | 新增 `rom.{evolution_x_version, android, manifest_branch}`、`kernel_release`、`droidspaces.enabled/patches` |
| 15 | `.github/workflows/build-matrix.yml` | 新输入 `evolution_x_version`、`enable_droidspaces`；默认值改为目标形态（`build_source_melt: false` / `build_source_evolution_x: true` / `build_kernelsu: true`）；**修 release slug**；concurrency 加 kernel_source |
| 16 | `.github/workflows/build-core.yml` | 新 `workflow_call` 输入透传 + build-info 记录（`evolution_x_version`、`kernel_release`、droidspaces 字段） |
| 17 | `patches/kernel-sources/evolution-x/658b84f/{series, 0001-…sysvipc-6-7-8.patch, 0002-…posix-mqueue.patch}`（新增） | **上游补丁原样入库**（实测 `git apply` 干净通过，无需重制） |
| 18 | `scripts/package-anykernel.sh` + `tests/test-toolchain-auto.sh` + `tests/test-workflow-policy.sh` | 修 §6.2 缺陷 4（`_caller_pkg` 优先级 + 测试清理 `release/`） |

### 7.2 随之要改的测试

| 文件 | 原因 |
|---|---|
| `tests/test-manager-policy.sh` | **不需要**（用 KernelSU，allowlist 不变） |
| `tests/test-kernel-sources.sh` | 若加了映射覆盖逻辑，断言 `evolution-x` 在映射命中时 pin 到 commit；preset 默认值不变 |
| `tests/test-matrix-generator.sh` | 若透传 `evolution_x_version`，补一条断言 |
| `tests/test-workflow-policy.sh` | 新输入/新关卡断言（`evolution_x_version`、`enable_droidspaces`、release slug 修正） |
| `tests/test-package-naming.sh` / `test-banner-text.sh` | 若 banner/命名加 ROM 行 |
| `tests/test-source-patches.sh` | 新增 evolution-x 补丁目录的存在性/可应用性检查 |
| `tests/test-evolution-x-versions.sh`（新增） | 映射文件 schema、ref 与 preset 一致性、commit 必须 40 位 hex |
| `tests/test-droidspaces-config.sh`（新增） | 必需 CONFIG 列表、禁止项、补丁 series 与 ref 门控 |

### 7.3 文档

`README.md`（输入表/默认值/兼容性）、`docs/versions.md`（新增 `658b84f…` 内核 pin + r563880c 工具链说明）、`docs/ARCHITECTURE.md`（如新增输入）。`docs/manager-matrix.md` 不需改（仍用 KernelSU）。

---

## 8. "只改 Evolution X 版本参数即可触发最新构建"的必要改动（已按真机证据收敛）

目标体验：编辑 `config/evolution-x-versions.json`（或 workflow 填 `evolution_x_version=12.5`）→ 点 Run → 出 Draft Release。

必须补齐的 10 件事（**用 KernelSU，不含 BakaSU 那 10 处**）：

1. **版本映射文件**（唯一真源，值全部来自真机实测）——字段建议：

   ```json
   { "12.4": {
       "android": "17",
       "manifest_branch": "cnb",
       "rom_build": "EvolutionX-17.0-20261112-marble-12.4-Official",
       "kernel_source_preset": "evolution-x",
       "kernel_repo": "Evolution-X-Devices/kernel_xiaomi_sm8450",
       "kernel_ref": "cnb",
       "kernel_commit": "658b84f13496fa94659905e5f29b31cfde41d0ce",
       "kernel_version": "5.10.269",
       "kernel_release_suffix": "-gki-g658b84f13496",
       "official_toolchain": "aosp-clang-r563880c",
       "defconfig_mode": "gki_fragments",
       "base_defconfig": "gki_defconfig",
       "config_fragments": ["vendor/waipio_GKI.config", "vendor/xiaomi_GKI.config",
                            "vendor/marble_GKI.config", "vendor/debugfs.config"],
       "droidspaces_profile": "gki-5.10",
       "susfs_kernel_branch": "gki-android12-5.10",
       "status": "verified-on-device",
       "evidence": "uname -r on device: 5.10.269-gki-g658b84f13496"
   } }
   ```

2. **resolver 读取映射**：`resolve-kernel-source.sh` 用映射里的 `kernel_repo/ref/commit/fragments` 覆盖 preset 输出；
   `SOURCE_REF` 需支持 40 位 commit（`actions/checkout` 的 `fetch-depth: 1` 可直接 checkout 指定 commit）。
3. **workflow 单一版本入口**：`build-matrix.yml` 增 `evolution_x_version`（string，默认取映射里标 `default: true` 的项），
   **不要**再维护第二份版本变量。
4. **commit 固定（本项目的命门）**：映射里的 `kernel_commit` 必须等于该 ROM 内核 release 串里的 `-g<sha>`，
   否则 vermagic 变、396 个 vendor 模块拒载（§3.4）。
5. **自动推导 commit 的小工具**（强烈建议）：`scripts/derive-kernel-pin.sh` —— 输入 `adb shell uname -r` 的输出，
   输出 `kernel_ref`/短 sha/40 位 sha（40 位用 `gh api repos/<repo>/commits/<short>` 补齐），
   并把 `kernel_version`、`kernel_release_suffix` 一起打印，供人工写入映射文件。这样"升级 ROM"就只剩
   "跑一条命令 → 把输出贴进 JSON"。
6. **defaults 改成目标形态**：`build_source_melt: false`、`build_source_evolution_x: true`、`build_kernelsu: true`、
   `enable_susfs: false`、`enable_droidspaces: true`、`toolchain: auto`、`lto: thin`、`build_scope: image-only`、
   `create_draft_release: true`。
7. **Droidspaces 开关 + 补丁**：`enable_droidspaces` → 应用 `patches/kernel-sources/evolution-x/658b84f/series`
   → `build-kernel.sh` 打开 5 项必需 CONFIG → 断言最终 `out/.config`。
8. **Release 命名修正**：tag/title 用 `marble-evolution-x-<ver>-droidspaces-kernelsu-r<run>`，数据取自 build-info
   （修 §6.2 缺陷 1：现在会生成 `marble-auto-rN`）。
9. **provenance 扩展**：build-info/json 增加 rom 版本、manifest 分支、`kernel_commit`、`kernel_release`、
   `evolution_x_version`、droidspaces 补丁来源与 commit。
10. **测试与 preflight 覆盖**：映射 schema 测试 + 组合校验（`enable_droidspaces` 必须配 GKI 补丁序列、
   `kernel_commit` 必须 40 位 hex 且与 `kernel_release_suffix` 末 12 位一致），让错误在 `setup` 阶段暴露，
    而不是编译 40 分钟后才失败。

> 版本升级（12.4→12.5）的理想流程：`adb shell uname -r` → `derive-kernel-pin.sh` → 把结果写进
> `evolution-x-versions.json` 一个块 → `preflight` 通过 → Run → Draft Release。**其余文件不动。**

---

## 9. 设备信息：已采集 / 仍未确认

### 9.1 已采集（2026-11-16，`adb` 只读，设备 `7306dbd8`）

| # | 信息 | 实测值 |
|---|---|---|
| 1 | ROM 版本 | Evolution X **12.4** / Android **17**（`ro.modversion=12.4`，`ro.evolution.version=17.0`） |
| 2 | 构建标识 | `EvolutionX-17.0-20261112-marble-12.4-Official`，`ro.build.date.utc=1794505894`（2026-11-12 17:51:34 UTC） |
| 3 | 设备代号 | `marble`（`ro.product.device`），机型 `23049RAD8C`，product `marble` |
| 4 | 运行内核 | `5.10.269-gki-g658b84f13496`，clang 21.0.0 (r563880c)，编译于 2026-11-12 17:59:07 UTC |
| 5 | 槽位 / 启动状态 | slot `_a`；`verifiedbootstate=green`、`vbmeta.device_state=locked`（疑似 PIF 伪造，仅记录不采信） |
| 6 | Root 状态 | **无 root**（`su` 不存在），内核无 KSU/SUSFS；已装 `me.weishu.kernelsu` 与 `com.resukisu.resukisu` 两个 Manager（均未激活） |
| 7 | vendor 模块 | `/vendor/lib/modules`、`/vendor_dlkm/lib/modules` 各 396 个 `.ko`（5.10 vermagic） |
| 8 | **官方内核 `.config`** | **已完整导出** → `reports/evidence/marble-12.4-stock-config.txt`（6249 项，46170 B；`/proc/config.gz` 权限 444，无需 root 即可读） |
| 9 | 关键 CONFIG | `MODVERSIONS=y`、`CFI_CLANG=y`、`LTO_CLANG_FULL=y`、`LOCALVERSION="-gki"`、`LOCALVERSION_AUTO=y`；`SYSVIPC/POSIX_MQUEUE/PID_NS/DEVTMPFS` 全为 `n`（详见 §5.3） |

> 顺带修正一条经验：`/proc/config.gz` 在 Evo X 上是 **444 世界可读**，不需要 root。**下次升级 ROM 后第一件事就是抓这个文件**，
> 它是判断"内核版本/fragment/kABI 基线"最省事的真值来源。

### 9.2 仍未确认（需要用户操作或只能靠真机试）

| # | 信息 | 现状 / 需要什么 |
|---|---|---|
| 10 | vendor 模块的 `vermagic` 与符号 CRC | 设备无 root 时 `modinfo` 不可用；可用 `strings /vendor_dlkm/lib/modules/*.ko | grep vermagic` 抽样（本轮未做），或等自编内核开机后看 `dmesg` |
| 11 | Recovery 版本（OFRP）与 HyperOS 固件基线 | `adb` 读不到；需用户看 Recovery 界面（12.4 changelog 要求 HyperOS 3 固件 + `OFRP-R11.1_7-Beta`） |
| 12 | 当前 boot 分区是否已有可用备份 | 用户自查；AnyKernel 刷入时会自动备份到 `/sdcard/marble-kernel-backup`，但**现在设备上还没有** |
| 13 | 用户是否要保留/清理旧 ReSukiSU Manager（`com.resukisu.resukisu`） | 建议先卸载，避免装完 KernelSU 后两个 Manager 抢 `su` |
| 14 | 官方构建所用 device/vendor 树 commit | 与内核无关（只影响 ROM 本身），本项目不需要 |
| 15 | 自编内核能否被官方 vendor 模块接受（kABI 实际是否保住） | **只有真机可验**（S3/S4 阶段看 `dmesg` 的 `disagrees about version of symbol` / 模块加载失败） |
| 16 | `llvm-22.1.8` 对这套 5.10.269 树的编译表现 | 未编译；官方用的是 r563880c（LLVM 21）。见 §11 风险 5 |
| 17 | Droidspaces 在 12.4 上的实际功能（Requirements 自检） | 需刷入带 Droidspaces 配置的内核后才能测（Phase 5） |

---

## 10. 已有能力 / 缺失能力

### 10.1 已有（可直接复用，勿重写）

| 能力 | 证据 |
|---|---|
| 数据驱动 preset / manager / SUSFS pin | `config/*.json` + 18 个策略测试 |
| 可复用 build-core（staged pipeline，120 min 超时） | `build-core.yml` |
| 工具链 SHA/commit 双固定 + 缓存 | `marble.env`、`build-core.yml:166-268` |
| 免费 runner 硬化（16 GiB swap、`JOBS<=2`、`thinlto-jobs=2`、磁盘清理） | `build-core.yml:135-157`、`build-kernel.sh:19-24,154-171` |
| 多级 ccache + ThinLTO 缓存，失败也保存 | `build-core.yml:273-329,432-444` |
| Manager 应用链路（allowlist + 固定 commit + `setup.sh`） | `resolve-refs.sh`、`patch-manager.sh` |
| Manager 版本解析（Wild 公式 + Makefile 注入） | `read-manager-version.sh` |
| SUSFS 集成（内核补丁 + rsync + Kconfig 校验） | `apply-susfs.sh` |
| preset 级源码补丁机制（已为 pa-gr 落地） | `apply-kernel-source-patches.sh` + `patches/kernel-sources/pa-gr/vauxite/` |
| AnyKernel3 固定 + 覆盖层 + 动 banner + boot 备份 | `package-anykernel.sh`、`ak3/anykernel.sh`（`block=boot`、`is_slot_device=auto`、`patch_vbmeta_flag=auto`、`dump_boot` 前先备份到 `/sdcard/marble-kernel-backup`） |
| ZIP 结构审计 + 体积/类型检查 | `audit-flashable-zip.sh` |
| build-info.txt/json + 摘要（单 build / matrix / release 三份） | `write-build-info-json.sh`、`generate-*-summary.sh` |
| Artifact attestation（`actions/attest`） | `build-core.yml:406-409` |
| ZIP-only Draft Release（校验和/结构/scope 一致性） | `prepare-promoted-release.sh` |
| preflight 静态门（bash -n / shellcheck / actionlint / 全测试 / 空白检查） | `preflight.yml` |
| Actions 全量 SHA 固定 + Dependabot | `dependabot.yml`、`test-workflow-policy.sh` |
| 历史 CI 验证 | `docs/verification/*`：5 个 manager × SUSFS 组合在 5.10 线上构建/打包/审计全过，ccache 命中 99.87% |

### 10.2 缺失（必须新增）

| 缺失 | 影响 |
|---|---|
| Evolution X 版本映射层（版本 → 内核 release → commit） | 无法"只改版本参数"，且容易误用分支 HEAD 导致 vermagic 不匹配 |
| 从 `uname -r` 反推 commit 的小工具 | 每次升级都要人工查 GitHub API |
| Droidspaces 配置层（`build-kernel.sh` 无任何 Droidspaces 逻辑） | 容器跑不起来 |
| Droidspaces 补丁入库（`patches/kernel-sources/evolution-x/<commit>/`） | 补丁只能靠现下载，不可复现 |
| Release tag/title 正确来源 | Draft Release 名会变成 `marble-auto-rN` |
| 本地静态门可复现性（缺 `patch`/`shellcheck`/`actionlint`） | 本机无法完整跑 preflight |

> **已不缺失**（第一版误判）：6.6 preset、BakaSU 全链路、SUSFS 参数化、设备证据采集——前者属于 12.5+ 的事，后两者已被"改用 KernelSU + 真机取证"绕开。

---

## 11. 兼容性风险（已按真机证据重排）

| # | 风险 | 级别 | 说明 / 缓解 |
|---|---|---|---|
| 1 | **源码 commit ≠ `658b84f…` → vermagic 不匹配** | 🔴 极高 | `CONFIG_LOCALVERSION_AUTO=y`，release 带 `-g<commit>`；396 个 vendor 模块会全部拒载。→ 映射文件里必须钉死 commit，不要去用"分支 HEAD" |
| 2 | Droidspaces kABI 实际是否保住 | 🟠 中高 | 补丁已实测可应用、设计上不移动偏移；但真正的验证只能靠真机加载 vendor 模块。缓解：严格按 §5.3 白名单，禁 `CFS_BANDWIDTH`/`CGROUP_PIDS`，不关 `MODVERSIONS` |
| 3 | `CFI_CLANG=y` + 我们的 clang ≠ r563880c | 🟠 中 | 官方用 LLVM 21.0.0 (r563880c)。kCFI 类型哈希与类型字符串有关、通常跨版本稳定，但**未验证**。缓解：首次构建保留 LTO（`thin`），先看编译与开机，再考虑对齐 r563880c |
| 4 | LLVM 22.1.8 对 5.10.269 树的编译适配 | 🟠 中 | 仓库现有 LOS 证据来自其它 5.10 树；22.1.8 比官方的 21 更新，可能出现新 warning→error。备选：新增 `aosp-clang-r563880c` preset（分支 `temp-android16-plus`，含 `clang-r563880c`） |
| 5 | `lto=none` 会连带关掉 `CFI_CLANG` | 🟡 低中 | Kconfig 依赖：`CFI_CLANG` 依赖 LTO。选 `none` 会偏离官方配置（虽然不会改 CRC）。→ 默认 `thin`，别用 `none` 做"快速验证" |
| 6 | `DEVTMPFS` 在官方 5.10 GKI 是关闭的 | 🟡 低中 | 打开是 Droidspaces 硬需求；官方文档把它列为 GKI 可开启项。若真机出现异常，这是第一个怀疑对象 |
| 7 | `CONFIG_CGROUP_DEVICE=n` / `NF_TABLES=n` | 🟡 低 | 官方**非 GKI** 清单要求，GKI 清单不要求；动 cgroup 结构有 kABI 风险 → 本轮不开 |
| 8 | Release 命名/tag 缺陷 | 🟡 低 | `marble-auto-rN`；修法见 §6.2 缺陷 1 |
| 9 | 缓存全冷 | 🟡 低 | `evolution-x` 的 ccache key 之前从未在 12.4 组合下命中；首次构建预计 30–60 min（5.10 比 6.6 轻） |
| 10 | 120 分钟 job 超时 + 免费 runner 内存 | 🟡 低 | 5.10 + CFI + thin LTO + swap 已在历史 CI 上跑通；风险低于 6.6 |
| 11 | 本机工具缺口 | 🟡 低 | 缺 `patch`（1 个测试失败）、`shellcheck`、`actionlint` |
| 12 | 旧 ReSukiSU Manager 残留 | 🟡 低 | 设备上 `com.resukisu.resukisu` 仍在；装完 KernelSU 后建议卸载，避免两个 Manager 争 `su` |

---

## 12. 测试方案

### 12.1 本地（Fedora，零编译）

```bash
# 0) 补齐本机静态门依赖（需 sudo，由用户执行）
sudo dnf install -y patch ShellCheck
#   actionlint：见 §12.4（可用容器或下载官方 release 二进制）

# 1) 语法 + 全策略测试
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh
bash tests/test-*.sh

# 2) shellcheck（与 preflight 同参数）
shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 scripts/*.sh scripts/lib/*.sh tests/*.sh

# 3) actionlint
actionlint

# 4) 空白
git diff --check
```

新增的针对性验证（都不需要编译内核）：

| 验证 | 方法 |
|---|---|
| 映射文件一致性 | `tests/test-evolution-x-versions.sh`：schema、`kernel_commit` 为 40 位 hex、`kernel_ref` 与 preset 一致、`config_fragments` 非空、`status` 枚举 |
| fragment 是否真实存在 | 用 GitHub API 逐个 HEAD 检查 `arch/arm64/configs/<fragment>`（离线可 mock，联机可直接查） |
| Droidspaces 补丁可应用性 | 抓取目标分支的 `include/linux/sched.h`（**只抓文件，不 clone、不编译**）→ `git apply --check` |
| 组合校验 | `validate-inputs.sh` 矩阵：`bakasu+surfs` 拒绝、`bakasu` 单开通过、`droidspaces` 无补丁序列拒绝、`susfs` 分支与 kernel 不匹配拒绝 |
| 打包命名 | `test-package-naming.sh` 增加 `bakasu` 用例 |
| 摘要渲染 | `test-summary-format.sh` 增加 BakaSU 行 |

### 12.2 CI 预检（低成本，必须全绿才允许正式构建）

`preflight.yml`（push/PR）已有全套静态门，Phase 2 的每个提交都应通过：
`bash -n` → `shellcheck` → `actionlint` → `bash tests/test-*.sh` → `git diff --check`。

### 12.3 阶梯式真机构建（每步都不刷机，全部 5.10 + KernelSU）

| 步骤 | 输入 | 目的 | Draft Release |
|---|---|---|---|
| S1 | `evolution_x_version=12.4` + `none` + `droidspaces=false` + `lto=thin` | 验证 commit pin / fragment / Image 能编出来；产物 `.config` 与真机 config 逐项 diff | 关 |
| S2 | S1 + `kernelsu` | 验证 KSU 应用、`CONFIG_KSU=y`、版本号解析、ZIP 命名/摘要 | 关 |
| S3 | S2 + `droidspaces=true` | 验证补丁应用、6 项 CONFIG 终态断言、禁用项未被打开 | 关 |
| S4 | S3 + `create_draft_release=true` | 验证 Release 命名/资产/notes（仍为 Draft） | **开（Draft）** |

**S1 的 `.config` 对比是本方案的关键验收点**（真机 config 已在 `reports/evidence/`）：除我们主动改动的 6 项 + `CONFIG_KSU` 外，
其余 6243 项的差异应**只剩少数无关项**。若出现大面积差异（尤其 `LOCALVERSION`、`MODVERSIONS`、`CFI_CLANG`、`LTO_*`、
`ARCH_WAIPIO`、`BUILD_ARM64_DT_OVERLAY`），说明 fragment 链或工具链不对，**不要继续往下走**。

每步产物审计（下载 artifact，不刷机）：

```
unzip -l AK3_marble_LOS_evolution-x_kernelsu-..._rN.zip      # 27 项 + Image
sha256sum -c *.zip.sha256
jq . build-info.json                                          # rom/kernel/manager/droidspaces 字段
grep -E '^CONFIG_(SYSVIPC|POSIX_MQUEUE|IPC_NS|PID_NS|DEVTMPFS|MODVERSIONS|CFI_CLANG|LTO_CLANG|LOCALVERSION)' .config
grep -E '^# CONFIG_(CFS_BANDWIDTH|CGROUP_PIDS) is not set' .config       # 必须仍是关闭
file kernel-source/release/Image
```

### 12.4 设备侧验证（仅在第 4 阶段之后、用户明确授权）

1. 备份 `boot` / `vendor_boot` / `dtbo`；确认 `/sdcard/marble-kernel-backup/` 已生成（AnyKernel 会自动备份 boot）。
2. 刷入 → 冷启动 → 记录 `uname -r`（应为 `5.10.269-gki-g658b84f13496`，**与官方一致**）。
3. `dmesg | grep -iE 'disagrees about version|module verification|Unknown symbol'` —— 空输出才算 vendor 模块通过。
4. `zcat /proc/config.gz` 与构建产物 `.config` diff（AGENTS.md §7.2 硬要求）。
5. `me.weishu.kernelsu` 打开 → 显示"已安装/工作中"，`su` 可用，模块可装。
6. Droidspaces：Settings → Requirements → Check Requirements 全绿。
7. 移除旧 `com.resukisu.resukisu` Manager（避免抢 `su`）。

### 12.5 判定标准（通过/不通过）

- 通过：S1–S4 全绿 + S1 的 config diff 收敛 + ZIP 审计通过 + 真机开机 + 无模块 CRC 报错 + KernelSU 正常 + Droidspaces 自检全绿。
- **仅 CI 成功不算通过**（AGENTS.md §15）。

---

## 13. 建议实施顺序

| 阶段 | 内容 | 产出 | 阻塞点 |
|---|---|---|---|
| **P2.0** | 地基：本机装 `patch`/`shellcheck`/`actionlint`，让 18 个测试全绿；`droidspaces-AGENTS.md` **保持不动** | 干净基线 | 装包需 sudo |
| **P2.1** | 版本映射层：`config/evolution-x-versions.json`（12.4 → commit `658b84f…`）+ resolver 读取 + `scripts/derive-kernel-pin.sh` + `test-evolution-x-versions.sh` | 版本参数成为唯一入口，commit 可自动推导 | 无 |
| **P2.2** | Droidspaces：把 `001…6_7_8` 与 `002…posix_mqueue` 原样放进 `patches/kernel-sources/evolution-x/658b84f/`，接上 `source_patches` + `enable_droidspaces` + `build-kernel.sh` 配置块与终态断言 | Droidspaces 内核可用 | 无（可应用性已实测） |
| **P2.3** | Release 命名修复（`marble-auto-rN` → `marble-evolution-x-12.4-…`）+ build-info/摘要扩展（`rom.*`、`kernel_release`、`droidspaces.*`） | Draft Release 名合规、provenance 完整 | 无 |
| **P2.4** | workflow 输入与 defaults（`evolution_x_version`、`enable_droidspaces`，默认形态 = Evo X + KernelSU + Droidspaces + Draft） | 一键构建 | 无 |
| **P2.5** | 文档：README 输入表、`docs/versions.md` 新 pin（含 r563880c 说明） | 一致 | 无 |
| **P3** | 第一次真机构建（§12.3 S1→S4），全程 Draft，**先解 S1 的 config diff** | Actions 产物 | 用户确认后才触发 |
| **P4** | Artifact 审计 + 报告 | `reports/build-audit.md` | 需产物 |
| **P5** | 设备验证（刷机） | 结论 | **需用户明确授权** |

**推荐理由**：commit pin（P2.1）是命门，先做；Droidspaces（P2.2）与 Release 命名（P2.3）互不依赖，可并行；
**不再有 BakaSU 与 6.6 preset 这两块工作**（前者被 KernelSU 替代，后者属于 12.5+）。

---

## 14. 本轮执行的验证命令（可复现）

```bash
# 仓库与测试
git -C ~/Projects/marble-kernel-builder status -sb && git log --oneline -5
bash tests/test-*.sh                      # 17/18，1 个因本机缺 patch 失败

# 真机取证（只读）
adb devices -l
adb shell 'getprop ro.evolution.build.version; getprop ro.build.version.release; getprop ro.modversion'
adb shell 'uname -r; cat /proc/version'
adb shell 'zcat /proc/config.gz' > reports/evidence/marble-12.4-stock-config.txt
adb shell 'pm list packages | grep -iE "ksu|resukisu|magisk"'
adb shell 'ls /vendor/lib/modules | wc -l'

# 分支事实
gh api repos/Evolution-X/OTA/contents/builds/marble.json?ref=cnb --jq .content | base64 -d
gh api repos/Evolution-X-Devices/kernel_xiaomi_sm8450/commits/cnb --jq '.sha,.commit.author.date'
gh api repos/Evolution-X-Devices/device_xiaomi_sm8450-common/contents/BoardConfigCommon.mk?ref=cnb --jq .content | base64 -d | sed -n '79,84p'

# Droidspaces 补丁在真机同源 5.10 树上的可应用性（严格、无 fuzz）
gh api repos/Evolution-X-Devices/kernel_xiaomi_sm8450/contents/include/linux/sched.h?ref=cnb --jq .content | base64 -d > /tmp/p510/include/linux/sched.h
gh api repos/Evolution-X-Devices/kernel_xiaomi_sm8450/contents/include/linux/sched/user.h?ref=cnb --jq .content | base64 -d > /tmp/p510/include/linux/sched/user.h
git -C /tmp/p510 apply --check /tmp/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch    # OK
git -C /tmp/p510 apply --check /tmp/002.5.10_or_lower_use_android_abi_padding_for_posix_mqueue.patch  # OK

# 工具链 / SUSFS 分支
curl -sS 'https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/temp-android16-plus/?format=JSON' | sed 1d | grep -o 'clang-r563880c'
git ls-remote --heads https://gitlab.com/simonpunk/susfs4ksu.git | grep -E '5.10|6.6'
```

---

## 15. 决策点（截至 2026-11-16 的状态）

| # | 事项 | 状态 |
|---|---|---|
| 1 | `droidspaces-AGENTS.md` 改名/提交 | ✅ **不改名、不提交**（用户已定） |
| 2 | Root 方案 | ✅ **改用官方 KernelSU**（用户已在设备上装 `me.weishu.kernelsu`）→ BakaSU 的 10 处改动全部取消 |
| 3 | 12.4 源码 pin | ✅ **已确定**：`658b84f13496fa94659905e5f29b31cfde41d0ce`（真机 `uname -r`），不需要"假设策略" |
| 4 | fragment 组合 | ✅ **已确定**：`gki_defconfig + waipio_GKI + xiaomi_GKI + marble_GKI + debugfs`（`TARGET_KERNEL_CONFIG` + 真机 config 双重验证） |
| 5 | KernelSU pin | ✅ **用 tag `v3.3.1`**（`0c0fdb960178fa12d80d6cbcfdcb6ad8be6a865d`） |
| 6 | 6.6 toolchain（12.5+ 才需要） | ⬜ 暂缓：本轮 5.10 先沿用 `llvm-22.1.8`；官方实际用 r563880c，若编译/开机异常再切 |
| 7 | Phase 3 是否按 S1→S4 阶梯（先解 config diff 再继续） | ⬜ 待确认 |
| 8 | 本机装 `patch` / `shellcheck` / `actionlint` | ✅ **已装并验证**（脚本 `scripts/dev-install-preflight-deps.sh`）→ 本地四道门全绿 |
| 9 | 是否清理设备上的旧 `com.resukisu.resukisu` Manager | ⬜ 待确认（建议装 KernelSU 内核后卸载） |

---

*本报告为只读审查产物：未修改任何构建代码，未触发 Actions，未对设备做任何写入操作，未创建 Release。
设备证据文件：`reports/evidence/marble-12.4-stock-config.txt`。*

---

## 16. Phase 2 实施记录（2026-11-16，本地完成，未 push / 未触发 Actions）

### 16.1 已完成

| 项 | 内容 | 关键文件 |
|---|---|---|
| P2.0a | 修 `PACKAGE_FAMILY` 优先级缺陷（`_caller_pkg` 捕获后从未使用） | `scripts/package-anykernel.sh` |
| P2.0b | 测试隔离：`test-toolchain-auto.sh` 改为在临时目录运行，不再在仓库根留 `release/kernel-source.env` | `tests/test-toolchain-auto.sh` |
| P2.0c | 打包命名回归用例（残留 env 注入 + `PACKAGE_FAMILY` 优先级） | `tests/test-package-naming.sh` |
| P2.1a | **版本映射层**：`12.4 → android 17 / cnb / commit 658b84f… / 5.10.269 / 4 fragments / gki-5.10 / gki-android12-5.10` | `config/evolution-x-versions.json`（新） |
| P2.1b | resolver 支持映射：`SOURCE_REF` 钉到 40 位 commit，保留 `SOURCE_REF_LABEL=cnb`；新增 `EVOLUTION_X_*`、`KERNEL_COMMIT`、`KERNEL_RELEASE_SUFFIX`、`DROIDSPACES_PROFILE`、`OFFICIAL_TOOLCHAIN`、`SUSFS_KERNEL_BRANCH_MAPPED`；**vermagic 交叉校验**（suffix 末 12 位必须等于 commit 前缀） | `scripts/resolve-kernel-source.sh`、`config/kernel-sources.json`（`version_map: true`） |
| P2.1c | **`derive-kernel-pin.sh`**：从 `uname -r`（或 `--adb`）反推 commit，直接输出可粘贴的映射块 | `scripts/derive-kernel-pin.sh`（新） |
| P2.2 | Droidspaces：上游两个补丁**原样入库**（含 SHA256 与来源说明）、`series`、`requires_env=ENABLE_DROIDSPACES` 门控、`match_refs` 同时接受分支名与 commit | `patches/kernel-sources/evolution-x/droidspaces/`（新）、`scripts/apply-kernel-source-patches.sh` |
| P2.2b | `build-kernel.sh`：Droidspaces 配置块（6 项必开）+ 终态断言 + `CFS_BANDWIDTH`/`CGROUP_PIDS` 强制关闭断言 + `lto=none` 会丢 CFI 的告警 | `scripts/build-kernel.sh` |
| P2.2c | `validate-inputs.sh`：Droidspaces 必须有 pin + profile + 补丁序列；SUSFS 内核分支改为白名单（5.10/6.6）并与映射交叉校验 | `scripts/validate-inputs.sh` |
| P2.3 | **Release 身份修正**：tag/title/rom 版本改为从 artifact 的 `build-info.txt` 派生并写入 `release-metadata.env`（不再受 `kernel_source` 默认 `auto` 影响），artifacts 之间不一致时硬失败 | `scripts/prepare-promoted-release.sh`、`.github/workflows/build-matrix.yml` |
| P2.3b | provenance 扩展：`build-info.txt/json` 增加 `rom.*`、`kernel.*`、`droidspaces.*` | `scripts/write-build-info-json.sh`、`build-core.yml` |
| P2.4 | workflow：新增 `evolution_x_version`、`enable_droidspaces`；默认值改为目标形态（Evo X + KernelSU + Droidspaces + Draft）；concurrency 加 `kernel_source`；ccache config hash 覆盖映射文件 | `build-matrix.yml`、`build-core.yml` |
| P2.4b | KernelSU pin → tag `v3.3.1` | `config/managers.json`、`docs/versions.md` |
| P2.5 | 文档：README 输入表/默认值/Release 命名、`docs/versions.md` 映射与 vermagic 说明 | `README.md`、`docs/versions.md` |

新增测试 3 个：`test-evolution-x-versions.sh`（含 vermagic 守卫用例）、`test-derive-kernel-pin.sh`（离线）、`test-droidspaces-config.sh`（门控 + 断言契约）。测试总数 17 → **20**。

### 16.2 本地验证（全部通过）

```
bash tests/test-*.sh                      20/20
bash -n scripts/*.sh scripts/lib/*.sh tests/*.sh     OK
shellcheck -e SC1090,SC1091,SC2016,SC2153,SC2154 …   OK
actionlint (1.7.12)                                  OK
git diff --check                                     OK
```

另做了三段"假 CI"串联验证（不编译内核）：

1. `resolve-kernel-source.sh` → `SOURCE_REF=658b84f…`、`SOURCE_REF_LABEL=cnb`、fragments 4 项、`DROIDSPACES_PROFILE=gki-5.10`。
2. `resolve-toolchain.sh`（auto）→ `TOOLCHAIN=llvm-22.1.8`。
3. `validate-inputs.sh` → 有 pin + profile 时通过；无 pin / 无补丁序列时正确拒绝。
4. `generate-build-matrix.sh`（Evo X + KernelSU）→ `evolution-x-kernelsu` 单行矩阵。
5. `apply-kernel-source-patches.sh` → `ENABLE_DROIDSPACES` 未设时跳过；设了但树为空时硬失败（证明门控真的打开）。

### 16.3 关键行为变化（评审重点）

| 变化 | 影响 |
|---|---|
| `evolution-x` 的 `SOURCE_REF` 从分支名变成 **40 位 commit** | checkout 可复现；`SOURCE_REF_LABEL` 保留 `cnb` 供展示与补丁门控 |
| `build-matrix.yml` 默认值翻转 | 默认 dispatch = Evo X + KernelSU + Droidspaces + Draft；Melt 改为显式勾选 |
| Draft Release tag 不再用 `inputs.kernel_source` | 12.4 + Droidspaces 时形如 `marble-evolution-x-12.4-droidspaces-r121` |
| Droidspaces 补丁默认**会**应用（`enable_droidspaces: true`） | 若只想编纯内核，dispatch 时取消勾选 |

### 16.4 未做（留给 Phase 3/4）

- 未提交、未 push、未触发 Actions、未刷机。
- `llvm-22.1.8` 对 5.10.269 的实际编译未验证（官方用的是 **r563880c/LLVM 21**）。若编译或开机异常，下一手是新增 `aosp-clang-r563880c` 工具链 preset（分支 `temp-android16-plus`，sparse path `clang-r563880c`）。
- S1 的 `.config` 逐项 diff 需要真实构建产物。

### 16.5 Phase 3 建议的第一条命令

```bash
gh workflow run build-matrix.yml \
  -f build_source_melt=false \
  -f build_source_evolution_x=true \
  -f build_none=true \
  -f build_kernelsu=false \
  -f enable_droidspaces=false \
  -f create_draft_release=false \
  -f evolution_x_version=12.4 \
  -f toolchain=auto -f lto=thin -f build_scope=image-only

# 下载 artifact 后：
diff -u <(sort reports/evidence/marble-12.4-stock-config.txt) \
        <(sort <artifact>/../.config)   # 只看与我们主动改动无关的差异
```
