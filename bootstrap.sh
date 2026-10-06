#!/data/data/com.termux/files/usr/bin/bash
# ================================================================
#  一行命令引导脚本
#  用法（ZeroTermux 里）：
#     curl -fsSL <本仓库 raw 地址>/bootstrap.sh | bash
#  或：
#     bash bootstrap.sh
# ================================================================
set -uo pipefail

REPO_URL="${M7H_REPO_URL:-https://github.com/YOUR_NAME/m7h-hsr-termux.git}"
BRANCH="${M7H_BRANCH:-main}"
DEST="${M7H_DIR:-$HOME/m7h-hsr-termux}"

R='\033[31m'; G='\033[32m'; Y='\033[33m'; C='\033[36m'; N='\033[0m'
ok()   { printf "${G}  ✓ %s${N}\n" "$*"; }
warn() { printf "${Y}  ! %s${N}\n" "$*"; }
die()  { printf "${R}  ✗ %s${N}\n" "$*"; exit 1; }

printf "${C}== March7thHoney Termux 部署引导 ==${N}\n\n"

# git 检查
if ! command -v git >/dev/null 2>&1; then
  warn "未安装 git，正在安装…"
  yes | pkg install git >/dev/null 2>&1 || die "git 安装失败，请手动: pkg install git"
fi
ok "git 就绪"

# 克隆或更新
if [ -d "$DEST/.git" ]; then
  warn "目录已存在，执行更新…"
  git -C "$DEST" fetch --depth 1 origin "$BRANCH" && git -C "$DEST" reset --hard "origin/$BRANCH" || warn "更新失败，使用现有内容"
  ok "更新完成"
else
  warn "克隆仓库…"
  git clone --depth 1 -b "$BRANCH" "$REPO_URL" "$DEST" || die "克隆失败。请检查 REPO_URL 是否正确、网络是否可达 GitHub"
  ok "克隆完成"
fi

chmod +x "$DEST"/*.sh 2>/dev/null || true

printf "\n${G}开始部署…${N}\n\n"
exec bash "$DEST/deploy.sh"
