#!/usr/bin/env bash
# ================================================================
#  推送辅助脚本（在电脑上运行，不是手机）
#
#  用法：
#     bash push.sh https://github.com/你的用户名/m7h-hsr-termux.git
#
#  前提：你已经在 GitHub 网页上创建了一个空仓库（不要勾选 README）
# ================================================================
set -uo pipefail

G='\033[32m'; R='\033[31m'; Y='\033[33m'; C='\033[36m'; N='\033[0m'
ok()   { printf "${G}  ✓ %s${N}\n" "$*"; }
warn() { printf "${Y}  ! %s${N}\n" "$*"; }
die()  { printf "${R}  ✗ %s${N}\n" "$*"; exit 1; }

REMOTE="${1:-}"
[ -n "$REMOTE" ] || die "请传入仓库地址，例如：
    bash push.sh https://github.com/你的用户名/m7h-hsr-termux.git"

cd "$(dirname "$0")" || die "无法进入脚本目录"
[ -d .git ] || die "当前目录不是 git 仓库"

printf "${C}==> 配置远程仓库${N}\n"
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE"
  ok "已更新 origin -> $REMOTE"
else
  git remote add origin "$REMOTE"
  ok "已添加 origin -> $REMOTE"
fi

printf "\n${C}==> 检查大文件${N}\n"
BIG=$(git ls-files -z | xargs -0 -I{} sh -c 'test -f "{}" && echo "$(stat -c%s "{}") {}"' 2>/dev/null | sort -rn | head -3)
echo "$BIG" | while read -r sz name; do
  [ -n "$sz" ] || continue
  mb=$(( sz / 1048576 ))
  if [ "$mb" -ge 100 ]; then
    warn "$name = ${mb} MB —— 超过 GitHub 单文件 100 MB 上限"
    warn "请改用 Git LFS："
    echo  "      git lfs install"
    echo  "      git lfs track 'dist/*.tar.gz'"
    echo  "      git add .gitattributes && git commit -m 'use lfs for dist'"
  else
    ok "$name = ${mb} MB"
  fi
done

# 分支名兜底
BRANCH="$(git branch --show-current 2>/dev/null || echo main)"
[ "$BRANCH" = "main" ] || { git branch -M main && BRANCH=main; ok "分支已重命名为 main"; }

printf "\n${C}==> 推送到 GitHub${N}\n"
warn "如果弹出登录窗口，请用 GitHub 账号登录（或用 Personal Access Token）"
if git push -u origin "$BRANCH"; then
  printf "\n${G}推送成功${N}\n\n"
  echo "手机端部署命令："
  echo "    su -c \"pkg install -y git && git clone --depth 1 $REMOTE ~/m7h && bash ~/m7h/deploy.sh wine\""
  echo
  echo "（若 GitHub 直连慢，加镜像：M7H_GH_PROXY=https://ghfast.top）"
else
  die "推送失败。常见原因：
    • 仓库地址写错
    • 未登录 / 凭据过期
    • 仓库非空（先在网页上建一个空的，或 git pull --rebase origin main）"
fi
