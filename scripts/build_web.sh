#!/usr/bin/env bash
# 构建 OpenHand Web 通用消息平台前端，并把产物写入 assets/web/
# （由 vite.config.ts 的 build.outDir 直接指向，所以这里只负责
# 安全清理 + install + build + 校验）。CI 与开发者本地均可运行。
set -euo pipefail

cd "$(dirname "$0")/.."
WEB_DIR="clients/web"
OUT_DIR="assets/web"
DEFAULT_PNPM_PACKAGE_MANAGER="pnpm@11.7.0"

if [[ ! -d "$WEB_DIR" ]]; then
  echo "[build_web] 找不到 $WEB_DIR" >&2
  exit 1
fi

resolve_pnpm_package_manager() {
  if ! command -v node >/dev/null 2>&1; then
    printf '%s' "$DEFAULT_PNPM_PACKAGE_MANAGER"
    return
  fi
  node - "$WEB_DIR/package.json" "$DEFAULT_PNPM_PACKAGE_MANAGER" <<'NODE'
const fs = require('fs');
const [, , packageJsonPath, fallback] = process.argv;
try {
  const raw = fs.readFileSync(packageJsonPath, 'utf8');
  const value = JSON.parse(raw).packageManager;
  process.stdout.write(
    typeof value === 'string' && value.trim() ? value.trim() : fallback,
  );
} catch {
  process.stdout.write(fallback);
}
NODE
}

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
    PNPM_PACKAGE_MANAGER="$(resolve_pnpm_package_manager)"
    echo "[build_web] 未检测到 pnpm，使用 corepack 自动激活 $PNPM_PACKAGE_MANAGER"
    corepack enable
    corepack prepare "$PNPM_PACKAGE_MANAGER" --activate
  else
    echo "[build_web] 缺少 pnpm，且系统没有 corepack；请先安装 pnpm" >&2
    exit 1
  fi
fi

pushd "$WEB_DIR" >/dev/null
if [[ -f pnpm-lock.yaml ]]; then
  pnpm install --frozen-lockfile
else
  pnpm install
fi
pnpm build
popd >/dev/null

# vite 当前不主动产出 assets/，但 pubspec.yaml 已声明 assets/web/assets/，
# 缺目录会触发 flutter analyze 的 asset_directory_does_not_exist 警告。
# 在 vite build 之后总是确保该目录存在 + 占位文件，让 rootBundle 永远扫得到。
mkdir -p "$OUT_DIR/assets"
[[ -f "$OUT_DIR/assets/.gitkeep" ]] || : > "$OUT_DIR/assets/.gitkeep"

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

# ---- 跨 feature import 边界检查 --------------------------------------------
# 硬约束：违规即 fail。P0 plan-1/2/3/5 完成后过渡开关已移除。
echo "[build_web] 跑 check_imports.dart"
if ! dart run scripts/check_imports.dart; then
  echo "[build_web] FAIL：检测到跨 feature 深路径 import；请走对应 feature 的 barrel" >&2
  exit 1
fi
