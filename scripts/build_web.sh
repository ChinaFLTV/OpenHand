#!/usr/bin/env bash
# 构建 OpenHand Web 通用消息平台前端，并把产物写入 assets/web/
# （由 vite.config.ts 的 build.outDir 直接指向，所以这里只负责
# 安全清理 + install + build + 校验）。CI 与开发者本地均可运行。
set -euo pipefail

cd "$(dirname "$0")/.."
WEB_DIR="clients/web"
OUT_DIR="assets/web"

if [[ ! -d "$WEB_DIR" ]]; then
  echo "[build_web] 找不到 $WEB_DIR" >&2
  exit 1
fi

# ---- 安全清理旧产物 ---------------------------------------------------------
# vite 已有 emptyOutDir，但当 outDir 越过项目根（这里是 ../../assets/web）
# 会触发警告并可能被未来版本拒绝；我们在调用 vite 之前显式按白名单清理，
# 既能消除残留，又能保证不会误删 assets/web 之外的目录。
if [[ -d "$OUT_DIR" ]]; then
  # 阻止 OUT_DIR 被改写成空串/根路径之类的危险值
  case "$OUT_DIR" in
    ""|/|.|..|./|../) echo "[build_web] 拒绝清理可疑目录: '$OUT_DIR'" >&2; exit 1;;
  esac
  echo "[build_web] 清理旧产物 → $OUT_DIR/{app.js,app.css,index.html,chunks,assets,*.map}"
  # 主入口 + sourcemap + 拆分子目录；public/ 内会被 vite 自动 copy 回来
  rm -f -- \
    "$OUT_DIR/app.js" \
    "$OUT_DIR/app.css" \
    "$OUT_DIR/index.html" \
    "$OUT_DIR"/*.map
  rm -rf -- "$OUT_DIR/chunks" "$OUT_DIR/assets"
else
  mkdir -p "$OUT_DIR"
fi

# ---- 工具链 -----------------------------------------------------------------
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

# ---- 校验关键产物已生成 -----------------------------------------------------
missing=()
for f in app.js app.css index.html; do
  [[ -s "$OUT_DIR/$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  echo "[build_web] 构建失败：缺少产物 ${missing[*]}" >&2
  exit 1
fi

echo "[build_web] OK → $OUT_DIR/{index.html,app.js,app.css}"
