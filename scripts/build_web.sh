#!/usr/bin/env bash
# 构建 OpenHand Web 通用消息平台前端，并把产物写入 assets/web/
# （已由 vite.config.ts 的 build.outDir 直接指向，所以这里只负责 install + build
# 与失败提示）。CI 与开发者本地均可运行。
set -euo pipefail

cd "$(dirname "$0")/.."
WEB_DIR="clients/web"

if [[ ! -d "$WEB_DIR" ]]; then
  echo "[build_web] 找不到 $WEB_DIR" >&2
  exit 1
fi

if ! command -v pnpm >/dev/null 2>&1; then
  if command -v corepack >/dev/null 2>&1; then
    echo "[build_web] 未检测到 pnpm，使用 corepack 自动激活 pnpm@latest"
    corepack enable
    corepack prepare pnpm@latest --activate
  else
    echo "[build_web] 缺少 pnpm，且系统没有 corepack；请先安装 pnpm" >&2
    exit 1
  fi
fi

pushd "$WEB_DIR" >/dev/null
pnpm install --frozen-lockfile=false
pnpm build
popd >/dev/null

echo "[build_web] OK → assets/web/index.html, app.js, app.css"
