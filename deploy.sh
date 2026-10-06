#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
#  March7thHoney 私服服务端 · ZeroTermux 一键部署
#
#  两种模式：
#    wine  (默认) Box64 + Wine —— 直接跑你现有的 win-x64 服务端
#                 完整保留 4.7v1 功能，无需源码
#    native       原生 ARM64 二进制 —— 性能最好，但只能服务 4.6 协议
#                 （读不了 4.7 的 Resource.bin 与数据库）
#
#  用法：
#    bash deploy.sh                # 默认 wine 模式
#    bash deploy.sh native         # 原生 ARM64 模式
#    M7H_GH_PROXY=https://ghfast.top bash deploy.sh   # GitHub 走镜像
#
#  前置条件（wine 模式必须）：
#    把你的服务端目录放到 /sdcard/Download/server/
#    即 PC 上 D:\Programs\server\ 整个目录
# ================================================================
set -uo pipefail

# ==================== 配置 ====================
MODE="${1:-wine}"
DISTRO="debian"
SERVER_SRC="${M7H_SERVER_SRC:-/sdcard/Download/server}"
GH_PROXY="${M7H_GH_PROXY:-}"
MIN_SPACE_WINE=3000      # MB
MIN_SPACE_NATIVE=1200
# ==============================================

TERMUX_PREFIX="/data/data/com.termux/files/usr"
TERMUX_HOME="/data/data/com.termux/files/home"
PD="$TERMUX_PREFIX/bin/proot-distro"
TENV="PATH=$TERMUX_PREFIX/bin:$TERMUX_PREFIX/bin/applets HOME=$TERMUX_HOME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

R='\033[31m'; G='\033[32m'; Y='\033[33m'; C='\033[36m'; B='\033[1m'; N='\033[0m'
step() { printf "\n${C}${B}==> %s${N}\n" "$*"; }
ok()   { printf "${G}  ✓ %s${N}\n" "$*"; }
warn() { printf "${Y}  ! %s${N}\n" "$*"; }
die()  { printf "${R}  ✗ %s${N}\n" "$*"; exit 1; }
gh()   { if [ -n "$GH_PROXY" ]; then echo "${GH_PROXY%/}/$1"; else echo "$1"; fi; }

printf "${B}${C}"
cat <<'BANNER'
  ┌──────────────────────────────────────────────────┐
  │  March7thHoney 服务端 · ZeroTermux 一键部署      │
  └──────────────────────────────────────────────────┘
BANNER
printf "${N}  模式: ${B}%s${N}\n" "$MODE"

case "$MODE" in
  wine|native) ;;
  *) die "未知模式 '$MODE'，可选: wine | native" ;;
esac

# ===============================================================
step "1/8  环境检查"
# ===============================================================
[ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ] || die "仅支持 aarch64，当前 $(uname -m)"
ok "架构 $(uname -m)"
[ "$(id -u)" = "0" ] || die "需要 root。请先执行 su，再运行：bash deploy.sh $MODE"
ok "root 权限正常"
[ -d "$TERMUX_PREFIX" ] || die "未检测到 Termux 环境（$TERMUX_PREFIX 不存在）"
ok "Termux 环境正常"

if [ "$MODE" = "wine" ]; then NEED=$MIN_SPACE_WINE; else NEED=$MIN_SPACE_NATIVE; fi
AVAIL_MB=$(df -m /data 2>/dev/null | awk 'NR==2{print $4}'); AVAIL_MB=${AVAIL_MB:-0}
if [ "$AVAIL_MB" -lt "$NEED" ]; then
  warn "可用空间 ${AVAIL_MB} MB < 建议 ${NEED} MB，可能中途失败"
else
  ok "可用空间 ${AVAIL_MB} MB（建议 ≥${NEED} MB）"
fi

# ===============================================================
step "2/8  网络检查"
# ===============================================================
if curl -sI -m 12 https://github.com >/dev/null 2>&1; then
  ok "GitHub 直连可达"
else
  warn "GitHub 直连失败。建议加镜像重跑，例如："
  echo  "      M7H_GH_PROXY=https://ghfast.top bash deploy.sh $MODE"
fi

# ===============================================================
step "3/8  安装 proot-distro"
# ===============================================================
if [ -x "$PD" ]; then ok "已安装"
else
  warn "安装 proot-distro…"
  su -c "$TENV pkg install -y proot-distro" || die "安装失败，请手动: pkg install proot-distro"
  [ -x "$PD" ] || die "proot-distro 仍未就绪"
  ok "安装完成"
fi

# ===============================================================
step "4/8  创建 Debian ARM64 环境"
# ===============================================================
DISTRO_DIR="$TERMUX_PREFIX/var/lib/proot-distro/installed-rootfs/$DISTRO"
if [ -d "$DISTRO_DIR/etc" ]; then ok "已存在，跳过"
else
  warn "安装 Debian（下载 rootfs，1~5 分钟）…"
  su -c "$TENV $PD install $DISTRO" || die "Debian 安装失败"
  [ -d "$DISTRO_DIR/etc" ] || die "Debian 目录异常: $DISTRO_DIR"
  ok "安装完成"
fi

run_in_debian() {   # $1 = 脚本文本
  printf '%s\n' "$1" > "$TERMUX_HOME/.m7h_inner.sh"
  chmod +x "$TERMUX_HOME/.m7h_inner.sh"
  su -c "$TENV $PD login $DISTRO -- /bin/bash $TERMUX_HOME/.m7h_inner.sh"
}

# ===============================================================
step "5/8  Debian 内安装基础依赖"
# ===============================================================
if [ "$MODE" = "wine" ]; then
  PKGS="wget tar gnu-which ca-certificates xz-utils file procps box64"
else
  PKGS="libicu72 libssl3 zlib1g ca-certificates tar procps"
fi
warn "apt 安装: $PKGS"
run_in_debian "
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends $PKGS
echo APT_DONE
" || warn "部分依赖安装失败，继续"
ok "依赖步骤完成"

# ===============================================================
#  分支 A：wine 模式
# ===============================================================
if [ "$MODE" = "wine" ]; then

step "6/8  安装 xow64（Wine 10.12-staging + Box64 0.3.7）"
XOW64_URL="$(gh https://raw.githubusercontent.com/ar37-rs/xow64-wine/refs/heads/main/proot_mode/xow64)"
warn "下载 xow64 安装器…"
run_in_debian "
cd \$HOME
if [ -x ~/xow64 ]; then echo '  已存在，跳过'; else
  rm -f ~/xow64
  wget -q -O ~/xow64 '$XOW64_URL' || { echo WGET_FAIL; exit 1; }
  chmod +x ~/xow64
fi
echo \"  xow64: \$(stat -c%s ~/xow64) 字节\"
" || die "xow64 下载失败。若被墙，请设置 M7H_GH_PROXY 后重跑"
ok "xow64 就位"

run_in_debian '~/xow64 proot=true' >/dev/null 2>&1 || true
warn "下载 Wine + Box64（体积大，请耐心，勿中断）…"
if run_in_debian '~/xow64 install'; then ok "Wine + Box64 安装完成"
else warn "xow64 install 未正常结束，重跑本脚本可续传"; fi

warn "验证 Wine 能否加载 Windows 程序…"
if run_in_debian '~/xow64 r cmd /c ver 2>&1 | head -6'; then ok "Wine 自检通过"
else warn "Wine 自检未通过，请手动排查：~/xow64 r cmd /c ver"; fi

step "7/8  部署服务端"
if [ -d "$SERVER_SRC" ]; then
  warn "从 $SERVER_SRC 复制…"
  rm -rf "$TERMUX_HOME/m7h-server"; mkdir -p "$TERMUX_HOME/m7h-server"
  cp -r "$SERVER_SRC"/. "$TERMUX_HOME/m7h-server"/ || die "复制失败"
  ok "已复制 $(find "$TERMUX_HOME/m7h-server" -type f 2>/dev/null | wc -l) 个文件"
elif [ -d "$TERMUX_HOME/m7h-server" ]; then
  ok "复用已有服务端目录"
else
  cat <<EOF

  ${R}找不到服务端目录${N}

  请把 PC 上的 ${B}D:\\Programs\\server\\${N} 整个目录拷到手机：
      ${B}$SERVER_SRC${N}
  即：手机内部存储 / Download / server

  必需文件：
      March7thHoney.exe    e_sqlite3.dll
      Config.json          Config/  (含 Resource.bin)

  也可以指定其它路径后重跑：
      M7H_SERVER_SRC=/sdcard/你的路径/server bash deploy.sh wine
EOF
  die "缺少服务端文件"
fi

for f in March7thHoney.exe Config.json Config/Resource.bin; do
  [ -e "$TERMUX_HOME/m7h-server/$f" ] && ok "找到 $f" || warn "缺少 $f"
done

step "8/8  生成启动脚本"
cat > "$TERMUX_HOME/start-m7h.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
exec $PD login $DISTRO -- /bin/bash $TERMUX_HOME/run-m7h.sh
EOS
cat > "$TERMUX_HOME/run-m7h.sh" <<'EOS'
#!/bin/bash
cd "$HOME/m7h-server" || { echo "服务端目录不存在"; exit 1; }
mkdir -p Config/Logs Config/Database
echo "=============================================="
echo " March7thHoney  (Box64 + Wine)"
echo " HTTP 分发 : 21000/tcp"
echo " 游戏服务  : 23301/udp (KCP)"
echo "=============================================="
exec "$HOME/xow64" r March7thHoney.exe
EOS
chmod +x "$TERMUX_HOME/start-m7h.sh" "$TERMUX_HOME/run-m7h.sh"

# ===============================================================
#  分支 B：native 模式
# ===============================================================
else

step "6/8  校验原生 ARM64 包"
NATIVE_TAR="$SCRIPT_DIR/dist/March7thHoney-arm64.tar.gz"
[ -f "$NATIVE_TAR" ] || die "缺少 $NATIVE_TAR
    该文件在仓库的 dist/ 目录下，请确认克隆完整（未用 --depth 1 以外的裁剪）"
ok "找到原生包 ($(du -h "$NATIVE_TAR" | cut -f1))"

step "7/8  部署原生服务端"
rm -rf "$TERMUX_HOME/m7h-native"; mkdir -p "$TERMUX_HOME/m7h-native"
tar -xzf "$NATIVE_TAR" -C "$TERMUX_HOME/m7h-native" --strip-components=1 || die "解压失败"
chmod +x "$TERMUX_HOME/m7h-native/March7thHoney"
ok "已部署 $(ls -1 "$TERMUX_HOME/m7h-native" | wc -l) 项"

step "8/8  生成启动脚本"
cat > "$TERMUX_HOME/start-m7h.sh" <<EOS
#!/data/data/com.termux/files/usr/bin/bash
exec $PD login $DISTRO -- /bin/bash $TERMUX_HOME/run-m7h.sh
EOS
cat > "$TERMUX_HOME/run-m7h.sh" <<'EOS'
#!/bin/bash
cd "$HOME/m7h-native" || { echo "目录不存在"; exit 1; }
echo "=============================================="
echo " March7thHoney  (原生 ARM64)"
echo " HTTP 分发 : 21000/tcp"
echo " 游戏服务  : 23301/udp (KCP)"
echo "=============================================="
exec ./March7thHoney
EOS
chmod +x "$TERMUX_HOME/start-m7h.sh" "$TERMUX_HOME/run-m7h.sh"
fi

# ===============================================================
#  通用：停止脚本 + 收尾
# ===============================================================
cat > "$TERMUX_HOME/stop-m7h.sh" <<'EOS'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f March7thHoney 2>/dev/null
pkill -f wineserver 2>/dev/null
pkill -f box64 2>/dev/null
echo "已尝试停止 服务端 / wineserver / box64"
EOS
chmod +x "$TERMUX_HOME/stop-m7h.sh"

printf "\n${G}${B}"
cat <<'DONE'
  ╔════════════════════════════════════════════════╗
  ║   部署完成                                     ║
  ╚════════════════════════════════════════════════╝
DONE
printf "${N}\n"
echo "启动服务端："
echo "    su -c \"bash $TERMUX_HOME/start-m7h.sh\""
echo
echo "停止服务端："
echo "    su -c \"bash $TERMUX_HOME/stop-m7h.sh\""
echo
echo "进 Debian 手动排查："
echo "    su -c \"$TENV $PD login $DISTRO\""
echo
printf "${Y}注意${N}\n"
if [ "$MODE" = "wine" ]; then
  echo "  • 首次启动会初始化 Wine 前缀（wineboot），可能 1~3 分钟"
  echo "  • Box64 有翻译损耗，启动会比 PC 慢（PC 上仅 1.96s）"
  echo "  • 若出现 X display / 图形相关报错，可忽略：服务端是控制台程序"
  echo "  • 先单独验证 Wine：进 Debian 后执行  ~/xow64 r cmd /c ver"
else
  echo "  • 原生 ARM64 模式性能最好，但只能服务 4.6 协议"
  echo "  • 它读不了 4.7 的 Resource.bin 与数据库（MemoryPack 字段数不匹配）"
  echo "  • 想要 4.7 功能请改用: bash deploy.sh wine"
fi
echo "  • ZeroTermux 通知栏务必【获取 wakelock】，否则息屏后会被杀"
echo "  • 放行端口 21000/tcp 与 23301/udp"
echo
