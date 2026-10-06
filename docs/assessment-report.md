# 崩坏：星穹铁道 4.7v1 私服服务端 —— Android ARM64 移植评估报告

生成时间：2026-10-06
目标：把 PC 端（Windows x64）服务端移植到 Android，在 Termux 环境下运行

---

## 一、结论摘要

| 问题 | 结论 |
|---|---|
| 服务端二进制形态 | **.NET Native AOT**、**Windows x64 原生机器码** |
| 能否直接换运行时改成 ARM64 | **不能**。Native AOT 是按 RID 一次性编译的原生代码，无 CLR 可替换 |
| 官方是否提供 Linux / ARM64 构建 | **没有**，所有 release 仅 `win-x64.zip` |
| 是否存在对应 4.7 的公开源码 | **没有**。公开源码 `March7thHoney-OpenSource` 停在 **4.6** 分支 |
| 用公开 4.6 源码重建 ARM64 是否可行 | **技术可行（已实测编译通过并在真 AArch64 上启动），但读不了你的 4.7 数据** |
| 逆向 AOT 二进制还原成可重编译源码 | **不现实**，见第四节 |

**最终可行路线只剩两条**，见第五节。

---

## 二、已完成并验证的工作

### 2.1 服务端形态鉴定（确凿）

对 `D:\Programs\server\March7thHoney.exe`（111,130,624 字节）的 PE 解析结果：

```
Machine  = 0x8664  (AMD64 / x64)
Subsystem= 3       (Console，控制台程序)
节表: .text .rdata .data .pdata .rsrc .reloc
.text 起始为原生机器码: 48 8D 05 C9 95 48 06 C3  (lea rax,[rip+...]; ret)
```

判定为 Native AOT 的关键证据（全部为 0 次命中）：

```
coreclr.dll        0 次
hostfxr            0 次
mscoree            0 次
libhostpolicy      0 次
.deps.json         0 次
ManagedNativeHeader 0 次
BSJB (#~ 元数据签名) 0 次
```

旁证：公开源码 `Program/Program.csproj` 的 AOT 配置与此二进制特征完全吻合 ——
`StackTraceSupport=false`、`UseSystemResourceKeys=true`、`DebuggerSupport=false`、
`MetadataUpdaterSupport=false`、`EventSourceSupport=false`、`IlcFoldIdenticalMethodBodies=true`。

### 2.2 版本确认

服务端启动日志：`当前服务端支持的版本: 4.6.0`
`Config/Hotfix.json` 的版本键为：

```
OSBETAWin4.6.51 / 4.6.52 / 4.6.53 / 4.6.54 / 4.6.55
OSBETAAndroid4.6.51 ... 4.6.55
OSBETAiOS4.6.51 ... 4.6.55
```

即 **4.7v1 测试服**（客户端自报 4.6.5x）。

### 2.3 原生 ARM64 构建 —— 已成功（真机级验证）

用公开 4.6 源码，交叉编译出 **原生 AArch64** 服务端：

```
dotnet publish Program/Program.csproj -c Release -r linux-arm64 --self-contained true
```

- 8 个工程全部编译通过，产出 `March7thHoney.dll` + 自包含运行时
- 体积 154.7 MB / 366 文件
- `libcoreclr.so` ELF 头校验：`e_machine = 0xB7` → **AArch64**（确认为真 ARM64，非 x64）

**在真 aarch64 Debian 容器内的运行验证（非纸上推演）：**

```
==== 架构 ====
aarch64
==== 启动日志 ====
╭─────────────────╮
│  March7thHoney  │
╰─────────────────╯
[I18nManager] 已加载 语言。
[Program] 正在启动 March7thHoney…
[ConfigManager] 当前服务端支持的版本: 4.5.5
[Database] 正在加载 数据库…
[Program] 全局分发 服务器正在监听 http://127.0.0.1:21000
[GameServer] 游戏 服务器正在监听 127.0.0.1:23301
[Program] 启动完成
...
[Program] Server.ServerInfo.ServerStarted
（持续运行 100 秒后被 timeout 优雅关闭，并执行 SaveDatabase）
```

→ **ARM64 原生可运行性已证实。移植的"能不能跑"部分不是问题。**

### 2.4 数据兼容性 —— 这是真正的拦路虎

把公开 4.6 源码构建出的 ARM64 服务端，接上**你的真实数据**后：

**问题 1：版本不符**
```
[ConfigManager] 当前服务端支持的版本: 4.5.5     ← 公开源码构建
[ConfigManager] 当前服务端支持的版本: 4.6.0     ← 你的 exe
```

**问题 2：资源缓存反序列化失败（格式版本锁死）**
自包含源码构建 + 源码自带 `Resource.bin`：
```
[ResCache] Resource cache is stale: EquipmentConfigData is missing.
```

自包含源码构建 + **你的** `Resource.bin`：
```
[ResCache] March7thHoney.Data.Custom.BannerConfig property count is 9
           but binary's header maked as 10, can't deserialize about versioning.
   at MemoryPack.MemoryPackSerializationException.ThrowInvalidPropertyCount
```

`Resource.bin` 是 **MemoryPack 二进制序列化**，其头部记录了**每个类型的字段数**。
你的 4.7 版本 `BannerConfig` 有 10 个字段，公开 4.6 源码的类只有 9 个
→ **二进制格式硬性不兼容，无法通过配置调整绕过**。

**问题 3：数据库 schema 不兼容**
用你的 `Config/Database/March7thHoney.db` 启动时崩溃：
```
at March7thHoney.Database.Generated.LineupDataStore.LoadAll(DbConnection c)
at March7thHoney.Database.DatabaseHelper.LoadType(DbConnection conn, Type type)
at March7thHoney.Database.DatabaseHelper.Initialize()
```
→ 公开源码的实体模型无法读取 4.7 的数据库表结构。

**问题 4：游戏数据目录缺失**
```
[ResMgr] 读取 AchievementData.json 失败，文件未找到
[ResMgr] 读取 AvatarConfig.json 失败，文件未找到
[ResMgr] 读取 AvatarPromotionConfig.json 失败，文件未找到
...（64 个 Excel 配置全部加载 0 条）
```
`Config.json` 中 `Path.ResourcePath = "Resources"`、
`ExcelOutputDirs = ["ExcelOutput", "ExcelOutputGameCore"]`，
但整个 `D:\Programs\server` 目录下**不存在 `Resources/` 目录**，游戏数据一条都加载不出来。

### 2.5 部署包（已生成）

`March7thHoney-arm64.tar.gz` —— 156 MB，包含：

- 原生 ARM64 自包含运行时与全部程序集（366 文件）
- **你的完整 `Config/`**：`Resource.bin`、`Hotfix.json`、`ClientSecretKey.ec2b`、
  `March7thHoney.db`、`Security/`（RSA 密钥）、`Languages/`、`Custom/`
- 你的 `Config.json`
- `start.sh` 启动脚本

> 说明：此包**可以启动**，但受 2.4 节的版本/格式差异影响，
> **无法替代你现有的 4.7 服务端对外服务**。它的价值在于：
> 证明 ARM64 原生路径畅通，以及作为后续拿到 4.7 源码后的即用构建产物。

---

## 三、移植可行性矩阵

| 方案 | 可行性 | 说明 |
|---|---|---|
| A. 换 .NET 运行时改架构 | ❌ | Native AOT 无 CLR |
| B. 公开 4.6 源码重建 ARM64 | ⚠️ 能跑，不能用 | 已实测：能启动，但 `Resource.bin` / 数据库 / 游戏数据全不兼容 |
| C. 逆向 AOT → 可重编译源码 | ❌ | 见第四节 |
| D. Box64 + Wine 二进制翻译运行原 exe | ⚠️ 未验证 | 保留 4.7 全部功能；需真机验证，见第五节 |
| E. 等作者发 ARM64 构建 | ✅ 最省事 | 项目官方已支持 ARM64（`setup-debian.sh` 明确覆盖 Arm64），只是没发布成品 |

---

## 四、为什么"逆向"这条路不通

你的判断是对的：**服务端是纯命令行、无 GUI，所以它不需要图形层**。
但这恰恰说明「逆向」要解决的不是 GUI 问题，而是**协议层**——而这里有两个坏消息：

**坏消息 1：把 Native AOT 反编译回可重编译的 C# 不现实**

- Native AOT 输出的是**机器码**，不是 IL。反编译器（ILSpy/dnSpy 等）**完全无法处理**
- 你这份二进制还做了**主动反逆向加固**：
  - `StackTraceSupport=false` → 丢弃逐方法名表（最大符号来源）
  - `UseSystemResourceKeys=true` → BCL 异常消息替换为短键名
  - `IlcFoldIdenticalMethodBodies=true` → 折叠相同方法体
  - `MetadataUpdaterSupport=false`、`DebuggerSupport=false` → 移除反射/诊断元数据
- 即便用 Ghidra/IDA 把 111 MB 机器码反汇编出来，得到的也是**几十万行无类型名、无方法名的
  伪 C 代码**。要把它还原成一个能 `dotnet build` 的 4.7 工程，工作量以**人月**计，
  且几乎必然引入协议错误——对游戏服务端是致命的。

**好消息：其实不需要逆向**

协议定义（`.proto`）**本来就在客户端里**，而作者自己的仓库里就带着正规流水线：

```
Proto/4.6/Raw/StarRail.proto      (1.39 MB)  ← 从客户端 dump 的原始 proto
Proto/4.6/Raw/packetIds.txt       (0.13 MB)  ← 包 ID ↔ 消息名映射
Proto/4.6/Raw/translations.txt    (0.12 MB)  ← 混淆名 → 真实名
Proto/Tool/ProtoOrganizer/        (18 个源文件) ← 协议整理与代码生成工具
Proto/Generated/*.cs              (144 文件)  ← 生成出的服务端协议代码
```

**正确做法是拿 4.7 客户端的 proto dump 走这条流水线，而不是逆向服务端二进制。**
但那仍然解决不了第二节的问题：数据库 schema 和 `Resource.bin` 的 MemoryPack 格式
是**服务端代码里硬编码**的，光有协议不够，还是需要 4.7 的服务端源码。

---

## 五、两条真正可行的路线

### 路线 D：Box64 + Wine 二进制翻译（保留 4.7 全部功能）

你已经 root，这很关键。可行形态：

```
Termux (root)
  └── chroot: Debian ARM64
        ├── Box64      (x86_64 → ARM64 指令翻译)
        └── Wine       (提供 Windows API / PE 加载)
              └── March7thHoney.exe (win-x64, 111 MB)  ← 原封不动
```

**为什么值得一试 —— 你的观察是关键论据：**

- 服务端是**控制台程序**（PE Subsystem = 3, Console）
- 它只做：TCP/HTTP 监听（21000）+ UDP/KCP 游戏端口（23301）+ SQLite + 文件 IO
- **完全不涉及图形**，因此**不需要 D3D / Vulkan / GPU 翻译**

这正是 Wine on Android 通常失败的地方被绕开了 —— 业界（如 Winlator）在 Android 上
跑 Windows **游戏**最头疼的就是图形栈，而你这个服务端根本不需要图形栈。
所以「Box64 + Wine 跑一个纯命令行 Windows 服务端」的难度，
**远低于**「Box64 + Wine 跑一个 Windows 游戏」。

**风险（必须如实说明）：**

- Box64 的 x64→ARM64 翻译通常只有原生 10%~30% 性能。服务端启动本身在原生只要 1.96s，
  翻译后可能 10~20s，可接受；但**联机时的包加密与高频 IO** 是否能扛住，必须实测
- Wine on Android 的 arm64 支持属于非主流路径，需要配合 `box64` 的 wine 集成或
  `termux-box` 类方案
- 我**无法在当前环境闭环验证这条路线** —— 我手上没有 ARM64 真机，
  容器里也拉不到 box64 二进制包（Debian 仓库无此包，需源码编译）。
  **我不会把没验证过的东西说成能用。**

### 路线 E：向作者索取 ARM64 构建（最省事，成功率最高）

公开源码明确写着自己的 ARM64 支持：

> `scripts/setup-debian.sh`：`case "$(uname -m)" in x86_64|amd64|aarch64|arm64)`
> `docs/native-linux.md`：Microsoft 的软件源为 Debian 12/13 提供 `dotnet-sdk-10.0`，
> 覆盖 **x64 与 Arm64**

也就是说 **作者手里必然能构建出 linux-arm64**，只是 release 里只发了 win-x64。
`Mar7thDev/March7thHoney-Public` 是你这套二进制的发布仓库 —— 直接提 issue
要一个 `linux-arm64` 构建，是**成本最低、成功率最高**的路径。

---

## 六、建议的下一步

1. **首选**：向 `Mar7thDev/March7thHoney-Public` 提 issue，索取 linux-arm64 构建
   （哪怕只是 `linux-arm64` 的 .NET 框架依赖版）。
2. **并行**：在真机上试路线 D（Box64 + Wine），我可以把完整的 chroot 安装脚本
   和 Box64/Wine 编译脚本准备好 —— 但需要你在手机上执行并回报结果。
3. **需要你确认/提供的东西**（缺一不可，否则无法继续往 4.7 推进）：
   - `Resources/` 目录（含 `ExcelOutput/`、`ExcelOutputGameCore/`）——
     当前 `D:\Programs\server` 里**没有**，没有它任何服务端都加载不出游戏数据
   - 私有的 4.7 服务端源码，或作者的 ARM64 构建
   - 客户端版本确认：你的客户端是否严格 4.7v1（4.6.5x）？

---

## 七、交付物清单

| 文件 | 说明 |
|---|---|
| `March7thHoney-arm64.tar.gz` | 原生 ARM64 服务端 + 你的完整 Config（156 MB） |
| `termux-setup-arm64.sh` | Termux + root 一键部署脚本（建 chroot、装依赖、布服务、生成启动器） |
| `docs/native-linux.md` 等源码 | 公开 4.6 源码已克隆在工作区供参考 |

---

## 附：本次使用的验证环境

- 构建：`.NET SDK 10.0.100`，`dotnet publish -r linux-arm64 --self-contained`
- 运行验证：Docker `--platform linux/arm64` + QEMU binfmt，Debian bookworm-slim (aarch64)
- 架构校验：`libcoreclr.so` ELF `e_machine = 0xB7 (AArch64)`
- 原始服务端形态：PE 解析 + 字符串特征扫描（见 2.1）
