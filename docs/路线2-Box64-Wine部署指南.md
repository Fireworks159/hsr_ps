# 路线 2 部署指南：Box64 + Wine

> 目标：在 ZeroTermux 里直接运行你现有的 **`March7thHoney.exe`（win-x64）**，
> **完整保留 4.7v1 服务端的全部功能** —— 不换源码、不改数据。

---

## 为什么这条路可行（已用证据确认）

我解析了你服务端的 **PE 导入表**（权威依据，不是字符串搜索）：

```
ADVAPI32  bcrypt  CRYPT32  IPHLPAPI  KERNEL32  ncrypt
ole32     OLEAUT32  Secur32  USER32   WS2_32
api-ms-win-crt-heap / math / string / convert / stdio / runtime / locale
共 18 个 DLL
```

**没有任何渲染层**：

| 检查项 | 结果 |
|---|---|
| `gdi32.dll` | ✗ 未导入 |
| `d3d9.dll` / `d3d11.dll` | ✗ 未导入 |
| `dxgi.dll` | ✗ 未导入 |
| `opengl32.dll` | ✗ 未导入 |
| `vulkan-1.dll` | ✗ 未导入 |
| PE Subsystem | `3` = `WINDOWS_CUI`（控制台） |

`USER32` 是控制台程序的标准导入（Wine 由 `wineconsole` 处理），**不涉及绘制**。

> **这就是关键**：Wine on Android 最容易失败的地方是图形栈翻译（D3D→Vulkan）。
> 你这个服务端是纯命令行程序，只做 `WS2_32`（TCP/UDP）+ SQLite + 文件 IO，
> **天然绕开了这个雷区**。你那句"只有命令行界面，没有 GUI"正是这条路的立足点。

---

## 技术原理

```
Windows 程序  March7thHoney.exe  (x64 PE)
      ↑ Wine 加载并实现 Windows API
x86_64 Linux 程序  wine  (Wine 10.12-staging, x86_64 版)
      ↑ Box64 把 x86_64 指令翻译成 ARM64
Android / ARM64  ZeroTermux + proot Debian
```

启动命令本质就是：

```bash
box64 <wine目录>/bin/wine March7thHoney.exe
```

**不需要实验性的 Box32**：因为 `Wine WOW64` 自带 32 位环境模拟，
而你的 exe 本身是纯 x64，直接由 Wine 加载。

---

## 组件来源（全部 GitHub 预编译包，手机端无需编译）

| 组件 | 版本 | 来源 |
|---|---|---|
| Wine | `10.12-staging`（x86_64 Linux，已为 Box64 打补丁） | `ar37-rs/xow64-wine` releases |
| Box64 | `0.3.7` | `ar37-rs/xow64-wine` components |
| 安装器 | `proot_mode/xow64`（90 KB shell 脚本） | 同上 |

`xow64` 是个封装好的安装/启动器，官方支持 **proot 模式**，且**不加 root 也能用**。

---

## 部署步骤

### 第 1 步：把服务端拷到手机

把 PC 上的整个目录：

```
D:\Programs\server\      ← 整个目录
```

拷到手机：

```
/sdcard/Download/server/
```

必需文件：`March7thHoney.exe`、`e_sqlite3.dll`、`Config.json`、`Config/`（含 `Resource.bin`）、`appsettings*.json`。

> 只拷这一个目录即可，**不需要**之前的 `March7thHoney-arm64.tar.gz`。

### 第 2 步：把部署脚本放进 ZeroTermux

```bash
cp /sdcard/Download/m7h-wine-deploy.sh "$HOME/"
```

### 第 3 步：一键部署

```bash
su
bash /data/data/com.termux/files/home/m7h-wine-deploy.sh
```

脚本会依次完成：

1. 校验 root / 架构 / **磁盘空间（需 ≥3 GB）**
2. **网络检查**（GitHub 不通会提前提醒你设镜像）
3. 安装 `proot-distro`
4. 创建 Debian ARM64 环境
5. Debian 内 `apt install wget tar gnu-which xz-utils box64`
6. 下载并安装 `xow64` → 拉取 **Wine 10.12-staging + Box64 0.3.7**
7. **自动验证 Wine 可用性**（跑 `cmd /c ver`）
8. 部署服务端 + 生成启停脚本

> Wine + 前缀约 1.5~2.5 GB，首次下载视网络可能需要较久。

### 第 4 步：启动

```bash
su -c "bash /data/data/com.termux/files/home/start-m7h-wine.sh"
```

首次启动会初始化 Wine 前缀（`wineboot`），可能 1~3 分钟。

**期望看到**（服务端自己的输出）：

```
[I18nManager] 已加载 语言。
[Program] 正在启动 March7thHoney…
[ConfigManager] 当前服务端支持的版本: 4.6.0      ← 你自己的数据，不再是 4.5.5
[Program] 全局分发 服务器正在监听 http://127.0.0.1:21000
[GameServer] 游戏 服务器正在监听 127.0.0.1:23301
[Program] 启动完成！用时 ...s
```

`4.6.0` 这个版本号能出来，就说明**它读到了你自己的 `Resource.bin` 和数据库**——
这正是路线 1 做不到的。

### 常用命令

```bash
# 停止
su -c "bash $HOME/stop-m7h-wine.sh"

# 进入 Debian 手动排查
su -c "/data/data/com.termux/files/usr/bin/proot-distro login debian"

# 单独测试 Wine（重要）
~/xow64 r cmd /c ver
```

### 让它常驻

| 事项 | 做法 |
|---|---|
| 防息屏被杀 | ZeroTermux 通知栏 → **获取 wakelock** |
| 防后台清理 | 关闭 Termux 电池优化、允许自启动 |
| 放行端口 | **21000/tcp** 与 **23301/udp** |
| 日志 | 服务端目录下 `Config/Logs/` |

---

## 我必须提前说清的风险（不夸大也不隐瞒）

**已确证的有利条件：**

- ✅ 服务端无任何图形依赖（导入表已证实）
- ✅ Wine / Box64 都是**预编译包**，手机端不需要编译
- ✅ `xow64` 把 Wine 针对 Box64 打过补丁并调好了 `BOX64_LD_LIBRARY_PATH`
- ✅ 服务端是 x64，不需要 Box32

**仍存在的不确定性（我无法在无 ARM64 真机的情况下闭环验证）：**

1. **性能**。Box64 翻译通常只有原生 10%~30%。服务端在 PC 上启动仅 **1.96s**，
   手机上可能 10~30s，可以接受；但**联机时的包加密（bcrypt/ncrypt）与高频 IO**
   能否扛住真实玩家负载，必须实测。
2. **CPU 特性检测**。NativeAOT 会做 CPU 特性探测。Box64 会包装 `CPUID`，
   但如果它报告的特性与实际翻译覆盖不符，可能崩溃。这是最可能出问题的地方。
   若崩溃，可调 Box64 环境变量（`BOX64_DYNAREC_SAFEFLAGS`、`BOX64_AVX` 等）绕开。
3. **proot 与 .NET/Wine 线程**。proot 对线程/mmap 有已知怪癖。你是 root，
   如果 proot 模式不稳，我可以再给一版**真 chroot + 同一套 Wine/Box64** 的方案
   （性能更好，但 `xow64` 的 proot 模式判定需要绕过）。

**建议的验证顺序**（先排除环境问题，再跑服务端）：

```bash
su -c "/data/data/com.termux/files/usr/bin/proot-distro login debian"
~/xow64 r cmd /c ver          # ① Wine 能跑 Windows 程序吗？
~/xow64 r regedit /S /dev/null # ② 更多 API 是否正常（可选）
```

①过了，再跑服务端。如果 ① 就不过，问题在 Wine/Box64 层，与服务端无关。

---

## 遇到问题怎么办

把这几样发我，我能准确定位：

1. **`~/xow64 r cmd /c ver` 的输出**（判断 Wine 层是否正常）
2. **服务端启动日志**（`m7h-server/Config/Logs/` 下最新那个）
3. **`~/xow64 install` 的完整输出**（判断组件是否下全）
4. 手机型号 + Android 版本 + 芯片

特别地：

- **Wine 初始化就失败** → 大概率是组件没下全，重跑脚本或手动 `~/xow64 install`
- **Wine 正常但服务端起不来** → 把日志给我，可能是 .NET 在 Wine 下的兼容问题
- **服务端起来了但客户端连不上** → 检查端口放行 + `Config.json` 里 `BindAddress` 是否为 `0.0.0.0`
- **GitHub 下载失败** → 把脚本顶部 `GH_PROXY` 设成镜像后重跑

---

## 与路线 1 的对比

| | 路线 1（原生 ARM64 重编译） | 路线 2（Box64 + Wine） |
|---|---|---|
| 服务端版本 | ❌ 只有 4.6，读不了你的数据 | ✅ **你的 4.7v1，原封不动** |
| 性能 | ✅ 原生，最好 | ⚠️ 翻译损耗，待实测 |
| 手机端编译 | 不需要 | 不需要（预编译包） |
| 磁盘占用 | ~160 MB | ~2.5 GB |
| 成功率 | 能启动但不能用 | **未知，需真机验证** |
| 依赖 | 无 | Box64 + Wine |

**结论：路线 2 是唯一能保留 4.7 功能的方案**，但它的成败取决于
Wine/Box64 能否稳定承载这个 NativeAOT 程序 —— 这一点只有真机能回答。
