<div align="center">

<img src="docs/assets/marble-banner.svg" alt="Marble Kernel Builder" width="720" />

<h3>用 GitHub Actions 给 Poco F5 / Redmi Note 12 Turbo 编内核</h3>

<p>
  <em>选源码 · 选 Root 方案 · 点 Run。</em><br/>
  <sub>5 个上游内核树 &middot; 4 个 KernelSU 家族管理器 &middot; 可选 SUSFS &middot; 不落地任何上游补丁</sub>
</p>

<p>
  <code>marble</code> &nbsp;·&nbsp; <code>marblein</code>
</p>

<p>
  <a href="https://github.com/wzk0/marble-kernel-builder/actions"><img src="https://img.shields.io/badge/GitHub_Actions-CI_builder-2088FF?style=for-the-badge&logo=githubactions&logoColor=white" alt="CI" /></a>
  <a href="https://github.com/wzk0/marble-kernel-builder"><img src="https://img.shields.io/badge/device-Poco_F5_·_RN12_Turbo-EF5350?style=for-the-badge&logo=xiaomi&logoColor=white" alt="Device" /></a>
  <a href="https://github.com/Evolution-X-Devices/kernel_xiaomi_sm8450"><img src="https://img.shields.io/badge/target-Evolution_X_12.4-7B1FA2?style=for-the-badge&logo=android&logoColor=white" alt="Evolution X" /></a>
</p>

<p>
  <a href="#-快速开始"><b>快速开始</b></a> &nbsp;·&nbsp;
  <a href="#-内核源码"><b>内核源码</b></a> &nbsp;·&nbsp;
  <a href="#-root-管理器"><b>Root 管理器</b></a> &nbsp;·&nbsp;
  <a href="#-droidspaces-容器支持"><b>Droidspaces</b></a> &nbsp;·&nbsp;
  <a href="#-踩坑记录本项目真实遇到过的"><b>踩坑记录</b></a> &nbsp;·&nbsp;
  <a href="docs/ARCHITECTURE.md"><b>架构</b></a>
</p>

</div>

---

> [!CAUTION]
> **刷自编内核可能开不了机、丢数据，保修也可能没了。**
>
> 仓库里的一切都是实验性的，**按现状提供**。刷之前请确认：
>
> | | 要求 |
> |:---:|---|
> | 🔓 | Bootloader 已解锁 |
> | 📱 | 只有 **Poco F5**（`marblein`）或 **Redmi Note 12 Turbo**（`marble`） |
> | 💾 | 有**同一 ROM 版本**的 `boot.img` 备份，且存在**手机之外** |
> | 🧩 | ZIP 的 ROM 家族要对得上（见[内核源码](#-内核源码)） |
>
> 刷了就是你自己承担风险。维护者不对变砖或数据丢失负责。

---

## ✨ 这是什么

这个仓库是一条 **GitHub Actions 流水线**，用来给 Poco F5 / Redmi Note 12 Turbo 编译可刷入的内核，
**全程不碰上游内核源码**。

核心是分离：

```
   本仓库                          上游内核树
   ──────                          ──────────
   workflows · scripts             Melt · LineageOS · Evolution-X
   config    · 打包                  aosp-pablo · pa-gr
                                   （干净克隆，只在临时工作区打补丁）
   永不落地到上游
```

Root 管理与 SUSFS 都在 **runner 的临时工作区**里应用，job 结束就丢弃，不会有任何提交回到内核仓库。

| | 能力 |
|:---:|---|
| 🧬 | **5 个内核源码**：Melt(HyperOS)、LineageOS、Evolution-X、aosp-pablo、pa-gr |
| 🔑 | **4 个 Root 管理器 + 无 Root 基线**：KernelSU、KernelSU-Next、SukiSU Ultra、ReSukiSU |
| 🛡️ | **可选 SUSFS**：`v2.2.0` / `v2.1.0` 固定版本，或自定义 ref |
| 🧊 | **Droidspaces**：GKI kABI 补丁 + 命名空间/IPC/devtmpfs 配置，一键开启 |
| ⚙️ | **可选 LTO**：`none` · `thin`（默认）· `full`，针对免费 runner 做过加固 |
| 📦 | **AnyKernel3 ZIP**：校验机型代号 + 刷前自动备份 boot |
| 🚀 | **并行矩阵构建**：一次编多个管理器，出一份合并报告 |
| 🔒 | **全部固定并留证**：工具链按 commit/SHA256 固定、管理器白名单、OIDC 产物签名 |

---

## 🚀 快速开始

| 步骤 | 做什么 |
|:---:|---|
| **1** | 打开 **Actions → Build Marble Kernel → Run workflow** |
| **2** | 勾 **Source: Evolution-X** 和 **Manager: KernelSU**，其余保持默认（`toolchain=auto`、`lto=thin`、`enable_droidspaces=true`） |
| **3** | 跑完下载 artifact 里的 ZIP 刷入；`create_draft_release=true` 会额外生成一个 Draft Release |

> [!TIP]
> **第一次用？** 先跑一次 `build_none=true` + `enable_droidspaces=false` 的纯内核构建，把"下载 → 校验 → 刷入 → 开机"整条链路先跑通，
> 再进入带 Root 的构建。见[安全构建顺序](#-安全构建顺序)。

命令行等价（`gh` 已登录时）：

```bash
gh workflow run build-matrix.yml \
  -f build_source_melt=false -f build_source_evolution_x=true \
  -f build_none=false -f build_kernelsu=true \
  -f enable_droidspaces=true -f enable_susfs=false \
  -f evolution_x_version=12.4 -f toolchain=auto -f lto=thin \
  -f build_scope=image-only -f enable_ccache=true \
  -f create_draft_release=true
```

---

## 🧬 内核源码

preset 用维护者名字命名，定义在 [`config/kernel-sources.json`](config/kernel-sources.json)。

| Preset | 上游树 | 默认 ref | defconfig | ROM 家族 |
|---|---|---|---|---|
| **`melt`** | [`mohdakil2426/android_kernel_xiaomi_marble`](https://github.com/mohdakil2426/android_kernel_xiaomi_marble) | `melt-rebase` | `marble_defconfig` | 🟢 官方 **HyperOS** |
| **`lineageos`** | [`LineageOS/android_kernel_xiaomi_sm8450`](https://github.com/LineageOS/android_kernel_xiaomi_sm8450) | `lineage-23.2` | GKI + fragments | 🟠 **LOS 系** ROM |
| **`evolution-x`** | [`Evolution-X-Devices/kernel_xiaomi_sm8450`](https://github.com/Evolution-X-Devices/kernel_xiaomi_sm8450) | `cnb` → **按 ROM 版本钉 commit** | GKI + fragments | 🟠 **LOS 系** ROM |
| **`aosp-pablo`** | [`aosp-pablo/android_kernel_xiaomi_sm8450`](https://github.com/aosp-pablo/android_kernel_xiaomi_sm8450) | `16` | GKI + fragments | 🟠 **LOS 系** ROM |
| **`pa-gr`** | [`pa-gr/android_kernel_xiaomi_sm8450`](https://github.com/pa-gr/android_kernel_xiaomi_sm8450) | `vauxite` | GKI + fragments | 🟠 **LOS 系** ROM |

> [!WARNING]
> **ROM 家族不能互换。** `melt` 是给**官方 HyperOS** 的；四个 LOS 系 preset 只给 **LineageOS 系自定义 ROM**。
> 跨家族刷入是这个机型最常见的变砖方式。

### Evolution X 版本 → 内核 commit（重点）

Evolution X 不发布构建清单，所以"这个 ROM 是用哪个内核编的"只能从内核自己的 release 串反推：
`CONFIG_LOCALVERSION_AUTO=y` 会把 commit 短 SHA 拼进去。

```
adb shell uname -r  →  5.10.269-gki-g658b84f13496
                       └ 版本 ┘      └ commit 前缀
```

映射写在 [`config/evolution-x-versions.json`](config/evolution-x-versions.json)：

| 字段 | 12.4 的值 |
|---|---|
| `kernel_commit` | `658b84f13496fa94659905e5f29b31cfde41d0ce` |
| `kernel_release_suffix` | `-gki-g658b84f13496` |
| `kernel_version` | `5.10.269` |
| `config_fragments` | `waipio_GKI` + `xiaomi_GKI` + `marble_GKI` + `debugfs` |
| `droidspaces_profile` | `gki-5.10` |

> [!IMPORTANT]
> **commit 变了 = vendor 模块全部拒载。** 模块的 `vermagic` 带完整 release 串，commit 不同 → `-g<别的sha>` →
> `vendor_boot` / `vendor_dlkm` 里那 396 个模块一个都加载不了（表现为不开机 / 黑屏 / 没 WiFi），而 CI 依然显示成功。
> 所以本仓库**从不使用分支 HEAD**，`resolve-kernel-source.sh` 里有一道守卫：release 后缀末 12 位必须等于 commit 前缀。

升级 ROM 后重新推导：

```bash
bash scripts/derive-kernel-pin.sh --adb --version 12.5
```

<details>
<summary><b>两种 defconfig 模式的区别</b></summary>

<br/>

**`single`**（Melt）——完整的设备 defconfig：

```bash
make marble_defconfig
```

**`gki_fragments`**（所有 LOS 系）——GKI 基座 + vendor 覆盖层：

```text
gki_defconfig
  + vendor/waipio_GKI.config     # SoC (SM8450)
  + vendor/xiaomi_GKI.config     # OEM
  + vendor/marble_GKI.config     # 设备
  + vendor/debugfs.config
```

这四件套来自 `device_xiaomi_sm8450-common` 对应分支的 `TARGET_KERNEL_CONFIG`，并且已用真机 `/proc/config.gz` 交叉验证。
**6.6 内核不走这套**：`cnb-6.6` 分支里没有 `TARGET_KERNEL_CONFIG`，改用 Kleaf，fragment 是 `vendor/waipio_perf.config`。

</details>

<details>
<summary><b>源码级补丁（CI 专用，不推上游）</b></summary>

<br/>

preset 可以携带**只在 CI 检出里应用**的补丁，永不推回上游。目前有两处：

| Preset | 目录 | 用途 |
|---|---|---|
| `pa-gr` @ `vauxite` | [`patches/kernel-sources/pa-gr/vauxite/`](patches/kernel-sources/pa-gr/vauxite/) | Clang 22 在 `sys_regs.c` 上的 `-Wuninitialized-const-pointer` |
| `evolution-x` | [`patches/kernel-sources/evolution-x/droidspaces/`](patches/kernel-sources/evolution-x/droidspaces/) | Droidspaces GKI kABI padding（仅 `enable_droidspaces=true` 时应用） |

上游修好后就删掉对应目录（各目录的 `README.md` 里写了判断依据）。

</details>

---

## 🔑 Root 管理器

只有**官方上游**仓库在白名单里，随机 fork 会被 [`validate-inputs.sh`](scripts/validate-inputs.sh) 拒绝，并有策略测试兜底。

| 管理器 | 纯内核 | + SUSFS | 实际来源 |
|---|:---:|:---:|---|
| `none` | ✅ | — | 无 Root 基线 |
| `kernelsu` | ✅ | ❌ | [`tiann/KernelSU`](https://github.com/tiann/KernelSU)，固定 tag `v3.3.1` |
| `kernelsu-next` | ✅ | ✅ | 官方 `@dev` → SUSFS 切到 [`pershoot@dev-susfs`](https://github.com/pershoot/KernelSU-Next) |
| `sukisu-ultra` | ✅ | ✅ | `@main` → SUSFS 切到官方 `@builtin` |
| `resukisu` | ✅ | ✅ | `@main`，管理器侧自带 SUSFS |

> [!NOTE]
> **唯一破例**是 `pershoot/KernelSU-Next@dev-susfs`（官方 `dev` 的 CI 验证过的 fork），只在 KernelSU-Next + SUSFS 时使用。
> **官方 KernelSU + SUSFS 始终被拒**，因为没有兼容的集成路径。

<details>
<summary><b>SUSFS 固定版本与用户态模块</b></summary>

<br/>

内核分支 `gki-android12-5.10`（6.6 内核对应 `gki-android15-6.6`），来自 [`simonpunk/susfs4ksu`](https://gitlab.com/simonpunk/susfs4ksu)：

| Preset | 目标 |
|---|---|
| `latest`（默认） | 分支 HEAD，动态跟踪最新提交与版本号 |
| `v2.2.0` | `4003ecf2d01c6d13fa8edf6c4f2607365738dc3d`（CI 验证过） |
| `v2.1.0` | `86114db0c49f20fa7857b8b559f3ab87cbc2d00d`（WildKernels GKI r4 pin） |
| `custom` | 用户自填 `susfs_ref` |

内核只是一半——刷完还要装匹配的 [用户态模块](https://github.com/sidex15/susfs4ksu-module/releases) 并配置隐藏规则。
最终配置会断言 `CONFIG_KSU=y` 与 `CONFIG_KSU_SUSFS=y`。

</details>

---

## 🧊 Droidspaces 容器支持

Droidspaces 需要一批 Android GKI 默认关闭的选项（PID/IPC 命名空间、SYSVIPC、POSIX 消息队列、devtmpfs）。
直接在 defconfig 里打开会移动结构体偏移 → **vendor 模块 CRC 校验失败 → 开机就崩**。
所以必须先给内核打 kABI padding 补丁，把字段塞进 ABI 预留槽位。

| 项 | 说明 |
|---|---|
| 补丁 | `patches/kernel-sources/evolution-x/droidspaces/`：`001…6_7_8`（task_struct 槽 6/7/8）+ `002…posix_mqueue`（5.10 及更旧） |
| 来源 | [`ravindu644/Droidspaces-OSS`](https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches)，原样入库并记录 SHA256 |
| 门控 | 只有 `enable_droidspaces=true` **且** 源码 ref 命中 `match_refs` 才应用 |
| 必开项 | `SYSVIPC` `POSIX_MQUEUE` `IPC_NS` `PID_NS` `DEVTMPFS` `NETFILTER_XT_MATCH_ADDRTYPE`（`build-kernel.sh` 会打开并对最终 `.config` 断言） |
| 严禁打开 | `CFS_BANDWIDTH` `CGROUP_PIDS` —— 会改调度器/cgroup 结构，数千导出符号 CRC 变化，没有 padding 能救 |
| 前提 | 必须按 commit 固定源码（补丁是按 commit 验证的），没有 pin 时 `validate-inputs.sh` 会拒绝 |

刷完开机后在 Droidspaces App 里 **Settings → Requirements → Check Requirements** 自检。
`--cpus` / `--pids-limit` 两项会是灰的（对应上面两个禁止项），这是**预期**，不是故障。

---

## ⚙️ 一次构建怎么跑

**`build-matrix.yml`** 是唯一入口：先把源码 × 管理器展开成矩阵，再为每个组合并行调用可复用的 **`build-core.yml`**。

```text
build-matrix.yml
  ├─ setup        策略快测 + 生成矩阵
  ├─ build[*]     build-core（每个矩阵项一个 job，fail-fast: false）
  ├─ aggregate    下载所有 marble-flash-*-r<run>，出一份合并摘要
  └─ release      可选：只放 ZIP 的 Draft Release
```

单个构建内部的固定管线：

```text
① Resolve   preset → toolchain → validate
② Prepare   克隆内核 → 源码级补丁 → 交换分区/磁盘 → 工具链缓存
③ Integrate manager → SUSFS/Droidspaces 补丁
④ Produce   编译 → AnyKernel3 打包 → 审计 + 签名 → 上传 → 保存缓存
```

> [!IMPORTANT]
> 管理器与补丁的应用都在 **③，runner 工作区内**。内核仓库是只读克隆，永远不会有提交回写。

<details>
<summary><b>全部工作流输入</b></summary>

<br/>

| 输入 | 默认 | 说明 |
|---|---|---|
| `build_source_melt` | `false` | 源码：Melt（官方 HyperOS） |
| `build_source_lineageos` | `false` | 源码：LineageOS |
| `build_source_evolution_x` | **`true`** | 源码：Evolution-X —— 默认目标 |
| `build_source_aosp_pablo` | `false` | 源码：aosp-pablo |
| `build_source_pa_gr` | `false` | 源码：pa-gr |
| `build_source_all` | `false` | 一次编全部 5 个源码 |
| `source_ref` | 空 | 覆盖 branch/tag/commit（空 = 用 preset 默认 / ROM 版本 pin） |
| `evolution_x_version` | 空 | Evolution X 版本；空 = 用 `config/evolution-x-versions.json` 的 `default` |
| `enable_droidspaces` | **`true`** | 应用 Droidspaces kABI 补丁并打开容器所需配置 |
| `build_none` | `false` | 无 Root 基线 |
| `build_kernelsu` | **`true`** | KernelSU（不启用 SUSFS） |
| `build_kernelsu_next` | `false` | KernelSU-Next |
| `build_sukisu_ultra` | `false` | SukiSU Ultra |
| `build_resukisu` | `false` | ReSukiSU |
| `enable_susfs` | `false` | 对 KSU-Next / SukiSU / ReSukiSU 生效 |
| `susfs_version` | `latest` | `latest` · `v2.2.0` · `v2.1.0` · `custom` |
| `susfs_ref` | 空 | 仅 `custom` 时使用 |
| `toolchain` | **`auto`** | `auto` 用 preset 推荐的；也可强制 `android-r416183b` / `llvm-22.1.8` |
| `lto` | `thin` | `none` · `thin` · `full` |
| `build_scope` | `image-only` | `image-only` 或 `full` |
| `enable_ccache` | `true` | 对象缓存 + `lto=thin` 时的 ThinLTO 缓存 |
| `create_draft_release` | **`true`** | 全绿后生成 ZIP-only Draft Release |

勾多个 `build_*` 会展开成并行 job（`fail-fast: false`），一个失败不影响其它。

</details>

<details>
<summary><b>工具链、LTO 与免费 runner 加固</b></summary>

<br/>

`toolchain=auto` 从 preset 解析，通常不需要手改。

| 工具链 | 用于 | 固定方式 |
|---|---|---|
| `android-r416183b` | Melt / HyperOS | 稀疏检出到 commit `6e3223f7…`，使用前校验 |
| `llvm-22.1.8` | LOS 系必需（armv9） | 官方 release 包 + SHA-256 `df0e1ecf…` |

GitHub 免费 runner 约 7 GiB 内存 / 4 核，所以开 LTO 时流水线会自动加固：

| 加固 | 行为 |
|---|---|
| 交换分区 | `lto != none` 时自动建（按目标文件系统可用空间自适应，最大 16 GiB） |
| LLVM 并行度 | `JOBS` 上限 **2**（自建机可 `JOBS_FORCE=1 JOBS=8`） |
| ThinLTO | `--thinlto-jobs=2`，缓存目录 `~/.cache/thinlto` |
| 磁盘 | 编译前清理宿主 SDK（dotnet / android / ghc / boost / swift） |

| 模式 | 何时用 |
|---|---|
| `none` | 最快，适合冒烟验证（注意：会连带关掉 `CFI_CLANG`，偏离官方配置） |
| **`thin`** | **默认**，免费 runner 的安全选择 |
| `full` | 最优化，内存吃紧，免费 runner 上容易 OOM（官方内核用就是 FULL） |

</details>

---

## 📦 产物

每个构建 job 上传 `marble-flash-<label>-<scope>-r<run>`（保留 30 天，不压缩）：

```text
marble-flash-evolution-x-kernelsu-image-only-r6/
├─ AK3_marble_LOS_evolution-x_kernelsu-v3.3.1-code32680_r6.zip
├─ …zip.sha256                 # 校验值
├─ build-info.txt              # 所有解析出的 commit + 工作流信息
├─ build-info.json             # 同上，机器可读（含 rom / kernel / droidspaces / config_sha256）
├─ config.txt                  # 最终 .config —— 用于和真机 /proc/config.gz 逐项比对
├─ summary.md                  # 人读报告（含 Cache 段）
├─ zip-audit.txt               # ZIP 结构审计
└─ ccache-stats.txt            # 原始 ccache -s
```

**命名规则**

```text
AK3_marble_<FAMILY>_<source>_<manager>[-version][-codeN][_susfs-vX.Y.Z]_rN.zip
           ▲        ▲        ▲                              ▲          ▲
           │        │        │                              │          └ run 编号
           │        │        │                              └ SUSFS 关闭时省略
           │        │        └ 管理器 id，基线构建是 "noroot"
           │        └ preset id
           └ MELT（melt）或 LOS（lineageos · evolution-x · aosp-pablo · pa-gr）
```

```text
AK3_marble_LOS_evolution-x_kernelsu-v3.3.1-code32680_r6.zip
AK3_marble_MELT_melt_ksunext-v3.2.0-code33203_susfs-v2.2.0_r121.zip
AK3_marble_MELT_melt_noroot_r124.zip
```

> [!NOTE]
> **LTO 与工具链故意不写进文件名**，否则没法读；它们在刷机 banner 和 `build-info.*` 里。

<details>
<summary><b>Draft Release 的命名与门禁</b></summary>

<br/>

release job 要求**每个**构建和合并摘要都成功。tag/title 由 `prepare-promoted-release.sh`
**从产物 `build-info.txt` 派生**（写进 `release-metadata.env`），不取工作流输入——
因为 `kernel_source` 输入的默认值是 `auto`：

```
tag    marble-<source>[-<rom版本>][-droidspaces]-r<run>    例：marble-evolution-x-12.4-droidspaces-r6
title  <Display> <rom版本> · <manager>[ · Droidspaces] · r<run>
```

- 资产**只有 ZIP**；校验值、元数据留在 Actions artifact 里。
- 附件前会重新校验 SHA256。
- 公开的 release notes 会剥掉 CI 专用的 **Cache** 段。
- 生成的是 **Draft**，要你手动 Publish（见[常见问题](#-常见问题)）。

</details>

---

## 🧪 安全构建顺序

每一步只多验一个变量，过了再往下走。

| 步骤 | 构建 | 验证什么 |
|:---:|---|---|
| **1** | `evolution-x` · `build_none` · `enable_droidspaces=false` · `lto=thin` | commit pin、fragment 链、工具链、打包、你的刷机流程 |
| **2** | 同上 + `build_kernelsu` | Root 集成（`CONFIG_KSU=y`） |
| **3** | 同上 + `enable_droidspaces=true` | kABI 补丁与容器配置项 |
| **4** | 同上 + `create_draft_release=true` | Release 命名、资产、notes |

**第 1 步的关键验收**：下载 artifact 里的 `config.txt`，和真机的 `/proc/config.gz` 逐项 diff：

```bash
diff <(grep -E '^(CONFIG_|# CONFIG_)' reports/evidence/marble-12.4-stock-config.txt | sort) \
     <(grep -E '^(CONFIG_|# CONFIG_)' config.txt | sort)
```

预期**只剩**：编译器版本号（`CC_VERSION_TEXT` / `CLANG_VERSION` / `AS_VERSION` / `LLD_VERSION`）、
`LTO_CLANG_THIN` 与 `FULL` 的互换、以及 `UAPI_HEADER_TEST`。
若出现大面积差异，说明 fragment 链或 commit 不对，**别继续往下走**。

---

## 📲 刷入

**需要**：解锁的 bootloader · `marble`/`marblein` 设备 · 家族匹配的 ZIP · **同版本 ROM** 的 `boot.img` 备份（存在手机外） · 对应的管理器 App。

| 步骤 | 做什么 |
|:---:|---|
| **1** | 下载 ZIP，先**校验 SHA-256**（值在 `build-info.json` 的 `zip_sha256` 或 artifact 的 `.sha256` 文件） |
| **2** | 用 Recovery（如 OrangeFox）**Install** 刷入，或用 [Kernel Flasher](https://github.com/fatalcoder524/KernelFlasher/releases) 刷到活动槽 |
| **3** | AnyKernel3 会校验代号，并在刷前把当前 `boot` 备份到 `/sdcard/marble-kernel-backup/` |
| **4** | 重启，安装/打开对应管理器 App |
| **5** | 需要 Droidspaces 就再装 App 跑 Requirements 自检；SUSFS 构建还要装用户态模块 |

> [!CAUTION]
> **救砖**：把**同一 ROM 版本**的 `boot.img` 刷回活动槽。A/B 设备注意槽位（或两个都刷）——这就是为什么第 3 步的备份不是可选项。

本仓库的 ZIP **只替换 boot 里的内核 Image**，不含 `vendor_boot` / `dtbo` / `.ko`：

| 分区 | 改不改 | 原因 |
|---|---|---|
| `boot` | ✅ 换内核 | 唯一需要动的 |
| `vendor_boot`（含 dlkm 模块） | ❌ | 靠 vermagic 一致加载，保持 ROM 原样 |
| `dtbo` / `vendor_dlkm` | ❌ | 同上 |

---

## 🔒 固定版本

所有会变的东西都固定并记录在案，完整表见 [`docs/versions.md`](docs/versions.md)。

| 组件 | 固定值 |
|---|---|
| **Evolution X 12.4 内核** | `Evolution-X-Devices/kernel_xiaomi_sm8450` @ `658b84f13496fa94659905e5f29b31cfde41d0ce`（5.10.269） |
| **Android Clang** | `clang-r416183b` @ `6e3223f76384455acde43affde3df0ea9df66c0d` |
| **LLVM** | `22.1.8`，SHA-256 `df0e1ecf…6384` |
| **AnyKernel3** | `dca9dc370838d919d56c1f59ec78b27a14a72c68` |
| **KernelSU** | tag `v3.3.1`（`0c0fdb96…`） |
| **SUSFS `v2.2.0`** | `4003ecf2d01c6d13fa8edf6c4f2607365738dc3d` |
| **Droidspaces 补丁** | 原样入库，SHA256 记在补丁目录的 `README.md` |

每 **2–4 周**或上游把 CI 搞挂时，复核 `config/managers.json`、`config/susfs-refs.json`、Droidspaces 补丁。

<details>
<summary><b>CI 可靠性实践</b></summary>

<br/>

| 方面 | 做法 |
|---|---|
| **Actions** | 所有第三方 action 按 commit SHA 固定 · Dependabot 每周 |
| **工具链** | Clang 使用前校验 commit；LLVM 解压前校验 SHA-256 |
| **产物留证** | 每个 ZIP 都有 OIDC artifact attestation |
| **权限** | 构建 job 只有 `contents: read`，只有 release job 有 `contents: write` |
| **策略** | 管理器 / SUSFS / LTO / 源码组合白名单在矩阵展开**之前**由测试拦截 |
| **对象缓存** | ccache 与 ThinLTO **失败也保存**，90% 处 OOM 的构建仍能暖下一次 |
| **并发** | concurrency 组含 source/toolchain/LTO/SUSFS/scope，互不取消 |
| **周检** | `weekly-melt-smoke.yml` 每周一 06:00 UTC 编一次 Melt 无 Root，捕捉上游漂移 |

</details>

---

## 🩹 踩坑记录（本项目真实遇到过的）

> 这一节都是从失败里换来的，改代码前先看一眼。

### 1. `vermagic` 不一致 → vendor 模块全部拒载（最贵的一课）

**现象**：构建全绿、ZIP 审计通过，刷入后黑屏/不开机/没 WiFi。
**原因**：`CONFIG_LOCALVERSION_AUTO=y` 把 commit 短 SHA 写进 `release`，模块 `vermagic` 带着它。
换了 commit → `5.10.269-gki-g<别的sha>` → `vendor_boot`/`vendor_dlkm` 里 396 个模块全部拒绝加载。
**处理**：源码一律按 **40 位 commit** 固定（不是分支）；`resolve-kernel-source.sh` 加守卫
（`kernel_release_suffix` 末 12 位必须等于 commit 前缀，否则直接失败）；升级 ROM 用 `derive-kernel-pin.sh` 从 `uname -r` 反推。

### 2. 误以为 12.4 用 6.6 内核（静态推断翻车）

**现象**：只看 `device_xiaomi_marble@cnb` 的 `evolution.dependencies`（它现在指向 `cnb-6.6`），得出"12.4 = 6.6 GKI"的结论。
**真相**：那份依赖是 ROM 发布**之后**（11/13–14）才改的；12.4（11/12 构建）用的是 **5.10.269**。
**处理**：以**真机**为准——`uname -r` = `5.10.269-gki-g658b84f13496`，`/proc/config.gz` 里 `CONFIG_DEBUG_FS=n`
正好对应 `vendor/debugfs.config`，四件套 fragment 全部对上。教训：**静态推断必须用设备事实兜底**。

### 3. fragment 链不是"一套用到底"

5.10 是四件套（`waipio_GKI`/`xiaomi_GKI`/`marble_GKI`/`debugfs`）；
6.6 树里 `waipio_GKI.config` 和 `debugfs.config` **不存在**，Kleaf 流程实际用 `vendor/waipio_perf.config`。
填错轻则 `Missing config fragment` 失败，重则编出 ABI 不一致的内核。判据是设备树的 `TARGET_KERNEL_CONFIG` 是否还在。

### 4. `resolve-refs.sh` 的 tag 解析把 SHA 也一起写进了环境文件

**现象**：

```
release/resolved-refs.env: line 6: v3.3.1: command not found
```

**原因**：`awk` 里 `sub()` 修改 `$2` 会重建 `$0`，裸 `print` 输出的是 `<sha> <tag>`。
之前管理器用分支 `main`（解析不到 tag）所以从未暴露；把 KernelSU 钉到 **tag `v3.3.1`** 后立刻炸。
**处理**：两个分支都改成 `print $2`，再加去空白兜底与静态回归断言。这个错误值还会污染 ccache key 和 ZIP 名，属于"静默错误"。

### 5. 要 `source` 的环境文件不能写裸空格

**现象**：`release-metadata.env: line 8: 12.4: command not found` —— release job 挂了，构建本身是好的。
**原因**：`release_title=Evolution-X 12.4 · …` 里的空格让 shell 把 `12.4` 当命令执行。
**处理**：所有值一律 `printf %q`；测试里**真的 `source` 一遍**再回读断言（只 diff 文本是抓不到的）。

### 6. runner 的 `/mnt` 是独立小盘

**现象**：`Setup swap for LTO` → `fallocate: No space left on device`，而 `df /` 显示 88 GiB 空闲。
**原因**：第三方 swap action 写死 16 GiB 且固定落在 `/mnt`。
**处理**：改成探测 `/mnt` 与 `/`、按可用空间收缩（留 4 GiB 余量）、`fallocate` 失败回落 `dd`、最终失败**只告警**不中断构建。

### 7. Droidspaces 补丁要按内核大版本选，而且会打不上

5.10 上 `001…fix_sysvipc_kabi_6_7_8` + `002…posix_mqueue` 都能用**严格** `git apply --check` 干净通过
（槽 1/2 已被 Android 与小米占用，6/7/8 空闲）。
但同一份补丁在 **6.6** 树上 hunk#2 打不上——尾部上下文被 `#ifdef CONFIG_RV` 替换了，届时必须重制。
所以补丁**原样入库**（带 SHA256），不在 CI 里现下载。

### 8. `IPC_NS` 不是想开就能开

`CONFIG_IPC_NS` 依赖 `SYSVIPC` 或 `POSIX_MQUEUE`。只写 `-e IPC_NS` 会在 `olddefconfig` 后被静默丢弃，
断言必须看**最终 `out/.config`**，不能只看 defconfig 文本。

### 9. 测试顺序敏感（已修）

早期 `test-toolchain-auto.sh` 会在仓库根留下 `release/kernel-source.env`，
导致后面跑的 `test-package-naming.sh` 假失败（打包族名变成上回残留的 `LOS`）。
现在该测试在临时目录运行；若你本地手动跑单个测试后看到 `release/`，先 `rm -rf release` 再跑全套。

### 10. `lto=none` 会顺手关掉 CFI

`CONFIG_CFI_CLANG` 依赖 LTO，选 `none` 会在 `olddefconfig` 时被关掉，偏离官方配置（官方是 `LTO_CLANG_FULL`）。
冒烟验证可以用，但正式包用 `thin`。

---

## ❓ 常见问题

**Q：仓库首页写 "No releases published"，但 Releases 页面能看到东西？**

因为那是 **Draft（草稿）**。草稿不算"已发布"，所以：
- 仓库右侧/首页的 Releases 区域显示 *No releases published*；
- 只有登录且有权限的人能在 Releases 页看到它，标签上会写 `Draft`；
- 它的下载链接里带 `untagged-…`（草稿没有正式 tag），发布后才变成 `releases/download/<tag>/…`。

要发布：打开该 Draft → 右上 **Edit**（铅笔）→ 取消勾选 *Set as a pre-release* / *Set as the latest release* 按需 →
点 **Publish release**。发布后 tag `marble-evolution-x-12.4-droidspaces-rN` 才会真正创建。

**Q：ZIP 名里的 `code32680` 是什么？**
管理器自己算出来的 version code（KernelSU 家族是 `30000 + git 提交数`），用来和 App 显示的数字对齐。

**Q：为什么 ZIP 里只有 `Image`，没有 vendor_boot/dtbo？**
本机型 `boot` 里放内核、`vendor_boot` 里放 vendor 模块。内核的 vermagic 与 ROM 自带的一致，
所以只换 `boot` 里的 Image 就够，vendor 侧保持原样最安全。

**Q：能不能直接改 `boot.img` 刷？**
不建议。AnyKernel3 会先 dump 当前 boot 再打补丁，还会自动备份；手工改容易漏掉 header/page size。

**Q：ccache 命中率怎么看？**
artifact 里的 `ccache-stats.txt`，或 summary 的 Cache 段。首次构建（或换管理器版本/配置）必然冷启动。

---

## 🗂️ 仓库结构

```text
marble-kernel-builder/
├── AGENTS.md                  # ★ 接手必读：设备事实、版本更新 SOP、踩坑记录
├── .github/workflows/
│   ├── build-matrix.yml       # ▶ 唯一入口
│   ├── build-core.yml         # 可复用的单次构建管线
│   ├── preflight.yml          # shellcheck · actionlint · 全部测试
│   └── weekly-melt-smoke.yml  # 每周上游漂移探针
├── scripts/                   # 真正的逻辑，可本地跑的 bash
├── config/                    # evolution-x-versions · kernel-sources · managers · pins
├── patches/kernel-sources/     # 每个 preset 的 CI 专用补丁
├── ak3/                       # AnyKernel3 覆盖层（anykernel.sh + banner）
├── skills/marble-kernel-ci/   # 操作型 skill（首次接入 / 版本更新 SOP）
├── tests/                     # 20 个策略/回归测试
└── docs/                      # ARCHITECTURE · versions · manager-matrix
```

> [!NOTE]
> **为什么逻辑放 bash 而不是 composite action？** 因为你能在笔记本上跑。
> 埋在 YAML 里的逻辑只能靠 push 到 CI 验证；`scripts/*.sh` + `tests/*.sh` 本地几秒就能跑完。

---

## 🔗 资源

<table>
<tr><td valign="top" width="50%">

**内核源码**

- [Melt / HyperOS](https://github.com/mohdakil2426/android_kernel_xiaomi_marble)
- [LineageOS SM8450](https://github.com/LineageOS/android_kernel_xiaomi_sm8450)
- [Evolution-X SM8450](https://github.com/Evolution-X-Devices/kernel_xiaomi_sm8450)
- [aosp-pablo SM8450](https://github.com/aosp-pablo/android_kernel_xiaomi_sm8450)
- [pa-gr SM8450](https://github.com/pa-gr/android_kernel_xiaomi_sm8450)

**工具**

- [AnyKernel3](https://github.com/osm0sis/AnyKernel3)
- [Kernel Flasher](https://github.com/fatalcoder524/KernelFlasher/releases)

</td><td valign="top" width="50%">

**Root 管理器**

- [KernelSU](https://github.com/tiann/KernelSU)
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [SukiSU Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)
- [ReSukiSU](https://github.com/ReSukiSU/ReSukiSU)

**容器 / 隐藏**

- [Droidspaces 内核配置](https://www.droidspaces.org/docs/kernel-configuration.html)
- [Droidspaces 补丁源](https://github.com/ravindu644/Droidspaces-OSS)
- [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu) · [SUSFS 模块](https://github.com/sidex15/susfs4ksu-module)

</td></tr>
</table>

---

## 🏆 致谢

这个 builder 只是胶水，硬的都是别人的工作。

**[osm0sis](https://github.com/osm0sis)** — AnyKernel3 · **[tiann](https://github.com/tiann)** — KernelSU ·
**[KernelSU-Next](https://github.com/KernelSU-Next)** · **[pershoot](https://github.com/pershoot)** — KSU-Next SUSFS 路径 ·
**[SukiSU Ultra](https://github.com/SukiSU-Ultra)** · **[ReSukiSU](https://github.com/ReSukiSU)** ·
**[simonpunk](https://gitlab.com/simonpunk)** — susfs4ksu · **[sidex15](https://github.com/sidex15)** — SUSFS 模块 ·
**[ravindu644](https://github.com/ravindu644)** — Droidspaces 与内核补丁 ·
**[WildKernels](https://github.com/WildKernels)** — CI / LTO / 缓存模式参考 ·
**Melt / LineageOS / Evolution-X / aosp-pablo / pa-gr 的维护者** — 内核树 ·
**marble 社区** — 设备支持。

---

## 💬 反馈

- 🐛 Builder 或 CI 问题 → **开 issue**
- 📐 原理 → [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- 🔖 精确 pin → [`docs/versions.md`](docs/versions.md)
- 🔑 管理器规则 → [`docs/manager-matrix.md`](docs/manager-matrix.md)
- 🤖 接手/自动化 → [`AGENTS.md`](AGENTS.md) + [`skills/marble-kernel-ci/`](skills/marble-kernel-ci/)

> 提问请附上 **run URL** 和 artifact 里的 `build-info.txt` —— 它包含所有解析出的 commit，能让构建第一次就复现出来。

---

<div align="center">
<sub>

**⚡ 用 GitHub Actions 构建，为 `marble`**

Poco F5 · Redmi Note 12 Turbo &nbsp;|&nbsp; KernelSU 家族 · Droidspaces · SUSFS（可选）

</sub></div>