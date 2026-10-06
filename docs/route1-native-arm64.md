# ZeroTermux 部署指南

> **先读这段（重要）**
>
> 本部署包构建自**公开的 4.6 源码**，实测在真 ARM64 上**可以正常启动**，
> 但**读不了你的 4.7 数据**：`Resource.bin` 的 MemoryPack 格式、数据库 schema
> 都与 4.7 不兼容。
>
> 所以：**这份指南能让你把服务端在 ZeroTermux 里跑起来，但它服务不了 4.7 客户端。**
> 完整原因见《移植评估报告.md》。
>
> 如果你要的是**能真正对外服务 4.7 客户端**，正确路径是：
> ① 向 `Mar7thDev/March7thHoney-Public` 要一个 `linux-arm64` 构建（作者项目本身支持 ARM64），
> 拿到后**用本文第 2 步之后的流程原样部署**；或
> ② 走 Box64 + Wine 二进制翻译运行你现有的 win-x64 服务端。

---

## 与普通 Termux 的差异（ZeroTermux 注意事项）

| 项目 | 说明 |
|---|---|
| HOME 路径 | `/data/data/com.termux/files/home`（ZeroTermux 相同） |
| 外部存储 | `/sdcard`（或 `/storage/emulated/0`）。**不能**把 chroot 放这里——sdcard 是 FUSE，无 Unix 权限位，chroot 必失败 |
| chroot 位置 | 必须放 `/data/local/` 之类真实 Linux 文件系统 |
| root | ZeroTermux 自带 `su`。**用真 chroot，不要用 proot-distro**——.NET 在 proot 下易出线程/进程问题 |
| 目录权限 | ZeroTermux 与 Termux 包名若不同（如 `com.termux.zero`），脚本里 `#!/data/data/com.termux/files/usr/bin/bash` 要改成对应包名。可用 `pkg show bash` 或直接 `which bash` 查 |

---

## 第 0 步：在电脑上生成 Debian ARM64 rootfs（一次性）

你电脑上 Docker 已可用。在 PowerShell 执行：

```powershell
# 生成 ARM64 Debian rootfs（约 30 MB 压缩后）
docker run --rm --platform linux/arm64 debian:bookworm-slim tar -C / -cf - . > debian-arm64-rootfs.tar
```

然后在电脑上把两个文件传到手机：

```powershell
# 方式 A：手机开了 USB 调试
adb push debian-arm64-rootfs.tar /sdcard/Download/
adb push "hsr-port\package\March7thHoney-arm64.tar.gz" /sdcard/Download/

# 方式 B：手动拷贝
# 把这两个文件拷到手机「下载」目录
```

> `March7thHoney-arm64.tar.gz` 在 [hsr-port/package/](hsr-port/package/) 目录里，55 MB。

---

## 第 1 步：把文件就位到 ZeroTermux 的 HOME

打开 ZeroTermux，**不要先 su**，直接执行：

```bash
# 从下载目录复制到 HOME（HOME 可写且是真实文件系统，最稳妥）
cp /sdcard/Download/debian-arm64-rootfs.tar     "$HOME/"
cp /sdcard/Download/March7thHoney-arm64.tar.gz  "$HOME/"

# 确认
ls -lh "$HOME"/debian-arm64-rootfs.tar "$HOME"/March7thHoney-arm64.tar.gz
```

然后把部署脚本也放进来。脚本内容见
[zerotermux-部署.sh](hsr-port/package/zerotermux-部署.sh)，你可以：

```bash
cp /sdcard/Download/zerotermux-部署.sh "$HOME/"
chmod +x "$HOME/zerotermux-部署.sh"
```

---

## 第 2 步：执行部署脚本

```bash
su
bash /data/data/com.termux/files/home/zerotermux-部署.sh
```

脚本会依次完成：

1. 校验 root、架构（aarch64）、`mount` 可用性、磁盘空间
2. 解压 rootfs 到 `/data/local/m7h/debian`
3. 挂载 `/proc` `/sys` `/dev` `/dev/pts`
4. 配置 DNS（优先复制系统 DNS，失败则写阿里/Google）
5. chroot 内 `apt-get install libicu72 libssl3 zlib1g ca-certificates procps`
6. 解压服务端到 chroot 内 `/opt/March7thHoney`
7. 生成启动器 `~/start-m7h.sh`、停止脚本 `~/stop-m7h.sh`、状态脚本 `status.sh`

预计耗时 2~5 分钟（主要花在 rootfs 解压和 apt）。

---

## 第 3 步：启动服务端

```bash
# ZeroTermux 里执行（脚本内部会自己 mount，不需要先 su）
su -c "bash /data/data/com.termux/files/home/start-m7h.sh"
```

**正常的话你会看到：**

```
======================================
 March7thHoney 服务端
 HTTP 分发 : 21000/tcp
 游戏服务  : 23301/udp (KCP)
======================================
╭─────────────────╮
│  March7thHoney  │
╰─────────────────╯
[I18nManager] 已加载 语言。
[Program] 正在启动 March7thHoney…
[ConfigManager] 当前服务端支持的版本: 4.5.5
[Database] 正在加载 数据库…
[Program] 全局分发 服务器正在监听 http://127.0.0.1:21000
[GameServer] 游戏 服务器正在监听 127.0.0.1:23301
```

看到「服务器正在监听」就说明 **ARM64 原生跑通了**。

> 注意这里显示 `4.5.5`，而你的服务端显示 `4.6.0` —— 这就是版本落差的直接体现。

---

## 第 4 步：验证与常用操作

```bash
# 查看端口与进程
su -c "chroot /data/local/m7h/debian /bin/bash /opt/March7thHoney/status.sh"

# 直接测分发接口（ZeroTermux 里跑）
curl -s -X POST http://127.0.0.1:21000/query_dispatch \
     -H 'Content-Type: application/json' \
     -d '{"version":"OSBETAWin4.6.51"}' | head -c 300

# 停止
su -c "bash /data/data/com.termux/files/home/stop-m7h.sh"

# 进 chroot 手动排查
su
R=/data/local/m7h/debian
mount -t proc proc $R/proc 2>/dev/null
mount -o bind /dev $R/dev 2>/dev/null
chroot $R /bin/bash
```

---

## 第 5 步：让它稳定常驻

| 事项 | 做法 |
|---|---|
| 防息屏被杀 | ZeroTermux 通知栏 → **获取 wakelock** |
| 防后台清理 | 系统设置 → 应用 → Termux/ZeroTermux → **关闭电池优化**、允许**自启动** |
| 放行端口 | 有防火墙/安全中心的话，放行 **21000/tcp** 与 **23301/udp** |
| 开机自启 | 用 Magisk 模块、`termux-boot`，或 Tasker 触发 `su -c "bash ~/start-m7h.sh"` |
| 日志 | chroot 内 `Config/Logs/` |

---

## 常见问题

**Q: `chroot: can't execute '/bin/bash': Permission denied`**
→ 你把 chroot 建在 `/sdcard` 上了。sdcard 是 FUSE，不支持 Unix 权限。必须放 `/data/local/`。

**Q: `apt-get update` 全部失败**
→ DNS 没配好。手动写入：
```bash
echo 'nameserver 223.5.5.5' | su -c "tee /data/local/m7h/debian/etc/resolv.conf"
```

**Q: 启动很慢（几十秒）**
→ 首次启动要加载 `Resource.bin` 与游戏数据，属正常。原生 x64 上是 1.96s，手机上慢一些正常。

**Q: 客户端连不上 / 连上没数据**
→ **这就是预期的结果**。原因是本包是 4.6 源码构建，与你的 4.7 数据不兼容
（`Resource.bin` MemoryPack 格式、数据库 schema、以及缺失的 `Resources/` 游戏数据）。
这不是部署问题，见《移植评估报告.md》第五节。

**Q: 服务端启动到一半就退出，日志最后是 `加载 数据库 失败`**
→ **这是已实测确认的预期行为**，不是你部署错了。我在真 aarch64 上完整模拟过本指南的
全流程，服务端会走到这里然后干净退出（退出码 0）：

```
[ResCache] Resource cache is stale: EquipmentConfigData is missing.
[ResMgr] 读取 AchievementData.json 失败，文件未找到
...（游戏数据目录 Resources/ 缺失，全部加载 0 条）
[Program] 加载 数据库 失败。
[Program] March7thHoney.Database.Lineup.LineupInfo property count is 5
          but binary's header maked as 6, can't deserialize about versioning.
   at March7thHoney.Database.Generated.LineupDataStore.LoadAll(DbConnection c)
   at March7thHoney.Database.DatabaseHelper.Initialize()
[Program] 关闭中…
```

根因和你 `Resource.bin` 那个错误完全一致：`LineupInfo` 在公开 4.6 源码里有 **5** 个字段，
你的 4.7 数据库里是 **6** 个。**MemoryPack 会在头部烙死每个类型的字段数，
字段数不一致就直接拒绝反序列化**——这类差异无法靠改配置绕过。

**Q: 想绕过这个、让服务端不要读你的数据库**
→ 可以，把 `Config/Database/March7thHoney.db` 删掉或改名，服务端会新建空库并正常常驻。
但这样一来客户端登录后**没有任何角色数据**，而且 `Resource.bin` 与游戏数据的
不兼容依旧存在，**仍然无法对外服务 4.7 客户端**。仅适合用来验证 ARM64 运行链路。

**Q: 想彻底卸载**
```bash
su
umount /data/local/m7h/debian/{proc,sys,dev/pts,dev} 2>/dev/null
rm -rf /data/local/m7h
rm -f /data/data/com.termux/files/home/{start-m7h.sh,stop-m7h.sh,debian-arm64-rootfs.tar,March7thHoney-arm64.tar.gz}
```

---

## 下一步（想真正服务 4.7 客户端）

拿到 ARM64 版服务端后，**本文第 2 步之后的流程可以原样复用**，只需替换
`March7thHoney-arm64.tar.gz` 里的程序部分（`Config/` 继续用你自己的）。

两条获取途径：

1. **向作者索取**：`Mar7thDev/March7thHoney-Public` 提 issue 要 `linux-arm64` 构建。
   作者的项目**本来就支持 ARM64**（`scripts/setup-debian.sh` 里明确处理 `aarch64|arm64`），
   release 只是没发出来。这是成本最低、成功率最高的路径。
2. **Box64 + Wine**：用二进制翻译直接跑你现有的 `March7thHoney.exe`（win-x64）。
   你的服务端是**纯控制台程序**（PE Subsystem=3），不碰图形，正好绕开了
   Wine on Android 最难的图形栈翻译。保留 4.7 全部功能。
   我可以在拿到你的真机反馈后，把 Box64/Wine 在 chroot 内的编译与配置脚本补上。
