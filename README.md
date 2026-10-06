# March7thHoney 私服服务端 · Termux/ZeroTermux 部署

把 PC 端（Windows x64）的 **崩坏：星穹铁道私服服务端** 部署到 Android 手机上，
在 ZeroTermux 环境中运行。

---

## 这个仓库解决什么问题

原服务端 `March7thHoney.exe` 是 **.NET Native AOT 编译的 Windows x64 原生程序**：

| 事实 | 证据 |
|---|---|
| 架构 | PE `Machine = 0x8664`（AMD64） |
| 形态 | Native AOT —— 无 `coreclr.dll` / `hostfxr` / `.deps.json` / CLR 元数据 |
| 子系统 | `WINDOWS_CUI`（纯控制台，**无图形依赖**） |
| 官方 ARM64 构建 | **不存在**，所有 release 只有 `win-x64.zip` |

Native AOT 是按 RID 一次性编译的原生代码，**没有 CLR 可以替换**，
所以不能简单地"换个运行时"跑在 ARM64 上。本仓库提供两条可行路线。

---

## 两条路线

### 路线 A：Box64 + Wine（**推荐，默认**）

直接运行你现有的 `March7thHoney.exe`，**完整保留 4.7v1 全部功能**。

```
Windows exe  →  Wine (x86_64 Linux 程序)  →  Box64 (翻译成 ARM64)  →  Android
```

**为什么可行**：我解析了服务端的 PE 导入表，共 18 个 DLL：

```
ADVAPI32  bcrypt  CRYPT32  IPHLPAPI  KERNEL32  ncrypt
ole32     OLEAUT32  Secur32  USER32   WS2_32  + 7 个 api-ms-win-crt-*
```

**没有任何渲染层** —— 无 `gdi32` / `d3d9` / `d3d11` / `dxgi` / `opengl32` / `vulkan-1`。
Wine on Android 最容易失败的图形栈翻译被天然绕开了。

组件全部来自 GitHub 预编译包（`ar37-rs/xow64-wine`），**手机端不需要编译**：

- Wine `10.12-staging`（x86_64 Linux，已为 Box64 打补丁）
- Box64 `0.3.7`

### 路线 B：原生 ARM64 二进制（回退）

从公开的 4.6 源码交叉编译出的**原生 aarch64** 服务端（`dist/` 目录，55 MB）。

- ✅ 真原生，性能最好，无翻译损耗（已在真 AArch64 上实测启动成功）
- ❌ **读不了 4.7 的数据**：`Resource.bin` 与数据库是 MemoryPack 二进制，
  头部烙死了每个类型的字段数（`BannerConfig 9 vs 10`、`LineupInfo 5 vs 6`），
  字段数不一致直接拒绝反序列化
- ❌ 只支持 4.6 协议

**所以路线 B 只适合验证 ARM64 运行链路，不能对外服务 4.7 客户端。**
详见 [docs/移植评估报告.md](docs/移植评估报告.md)。

---

## 快速开始

### 前置条件

1. **已 root 的 Android 手机** + ZeroTermux
2. **≥3 GB 可用空间**（路线 A）
3. **把服务端目录拷到手机** —— 这是唯一需要手动准备的东西：

   ```
   PC:  D:\Programs\server\        ← 整个目录
   手机: /sdcard/Download/server/
   ```

   必需文件：`March7thHoney.exe`、`e_sqlite3.dll`、`Config.json`、`Config/`（含 `Resource.bin`）、`appsettings*.json`

   > `Config/` 里含你的数据库、RSA 密钥、资源缓存，这些**不进本仓库**。

### 一行命令部署（路线 A）

```bash
su -c "pkg install -y git && git clone --depth 1 https://github.com/YOUR_NAME/m7h-hsr-termux.git ~/m7h && bash ~/m7h/deploy.sh wine"
```

或者分两步：

```bash
git clone --depth 1 https://github.com/YOUR_NAME/m7h-hsr-termux.git ~/m7h
su
bash /data/data/com.termux/files/home/m7h/deploy.sh wine
```

脚本会自动完成：

1. 环境检查（root / 架构 / 空间）
2. 网络检查（GitHub 不通会提示设镜像）
3. 安装 `proot-distro` → 创建 Debian ARM64
4. `apt` 安装 `wget tar gnu-which xz-utils box64`
5. 下载并安装 `xow64` → 拉取 **Wine 10.12-staging + Box64 0.3.7**
6. **自动验证 Wine 可用性**（`cmd /c ver`）
7. 部署服务端 + 生成启停脚本

### GitHub 被墙怎么办

```bash
su
M7H_GH_PROXY=https://ghfast.top bash ~/m7h/deploy.sh wine
```

### 启动 / 停止

```bash
# 启动
su -c "bash /data/data/com.termux/files/home/start-m7h.sh"

# 停止
su -c "bash /data/data/com.termux/files/home/stop-m7h.sh"
```

**首次启动**会初始化 Wine 前缀（`wineboot`），可能 1~3 分钟。

### 成功的标志

服务端日志出现你自己的版本号（而不是路线 B 的 `4.5.5`）：

```
[ConfigManager] 当前服务端支持的版本: 4.6.0
[Program] 全局分发 服务器正在监听 http://127.0.0.1:21000
[GameServer] 游戏 服务器正在监听 127.0.0.1:23301
```

`4.6.0` 能出来，说明它读到了你自己的 `Resource.bin` 和数据库。

---

## 路线 B（原生 ARM64）

```bash
su
bash ~/m7h/deploy.sh native
```

---

## 验证与排查

**先单独验证 Wine**，再跑服务端：

```bash
su -c "/data/data/com.termux/files/usr/bin/proot-distro login debian"
~/xow64 r cmd /c ver        # 应输出 Windows 版本号
```

这条过了说明 Wine/Box64 环境正常，问题就只在服务端本身。

出问题时把这三样发出来：

1. `~/xow64 r cmd /c ver` 的输出
2. 服务端目录 `Config/Logs/` 下最新日志
3. `~/xow64 install` 的完整输出

常见问题见 [docs/路线2-Box64-Wine部署指南.md](docs/路线2-Box64-Wine部署指南.md)。

---

## 已知风险（如实说明）

路线 A 的有利条件已经用证据确认（无图形依赖、全预编译包、Wine 已针对 Box64 调好）。
**但以下两点必须在真机上验证，无法在 PC 上闭环：**

1. **性能**。Box64 翻译通常只有原生 10%~30%。服务端在 PC 上启动仅 **1.96s**，
   手机上预计 10~30s（可接受）；但**联机时的 bcrypt/ncrypt 包加密与高频 IO**
   能否承载真实玩家负载，未知。
2. **CPU 特性检测**。NativeAOT 会做 CPUID 探测，Box64 会包装 CPUID。
   若报告的特性与实际翻译覆盖不符，可能崩溃。可通过
   `BOX64_DYNAREC_SAFEFLAGS` 等环境变量绕开。

---

## 目录结构

```
.
├── bootstrap.sh                     # 一行命令引导（clone + deploy）
├── deploy.sh                        # 主部署脚本（wine / native 两种模式）
├── dist/
│   └── March7thHoney-arm64.tar.gz   # 路线 B 用的原生 ARM64 包
├── docs/
│   ├── 路线2-Box64-Wine部署指南.md   # 路线 A 详解
│   ├── 原生ARM64部署指南.md          # 路线 B 详解（含 chroot 方式）
│   └── 移植评估报告.md               # 完整技术鉴定与可行性分析
└── LICENSE
```

---

## 不包含什么（重要）

本仓库**不包含**：

- `March7thHoney.exe` —— 上游作者的二进制，请自行获取
- `Config/` 目录 —— 含你的数据库、RSA 私钥、资源缓存，属个人数据
- `debian-arm64-rootfs.tar.gz` —— 可用一条 Docker 命令生成，见下

生成 Debian ARM64 rootfs（如需 chroot 方式）：

```bash
docker run --rm --platform linux/arm64 debian:bookworm-slim \
  tar -C / --exclude=./proc --exclude=./sys --exclude=./dev \
  -czf - . > debian-arm64-rootfs.tar.gz
```

---

## 致谢

- [ptitSeb/box64](https://github.com/ptitSeb/box64) — x86_64 → ARM64 翻译层
- [ar37-rs/xow64-wine](https://github.com/ar37-rs/xow64-wine) — Termux 上的 Wine + Box64 预配置方案
- [Mar7thLover/March7thHoney-OpenSource](https://github.com/Mar7thLover/March7thHoney-OpenSource) — 公开的 4.6 服务端源码

## 许可证

见 [LICENSE](LICENSE)。本仓库仅为部署脚本与文档；
服务端程序与其资源文件的版权归原作者所有。
