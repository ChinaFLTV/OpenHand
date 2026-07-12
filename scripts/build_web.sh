#!/usr/bin/env bash
# 构建 OpenHand Web 通用消息平台前端，并把产物写入 assets/web/
# （由 vite.config.ts 的 build.outDir 直接指向，所以这里只负责
# install + 安全清理 + build + 校验）。CI 与开发者本地均可运行。
set -euo pipefail

cd "$(dirname "$0")/.."
readonly WEB_DIR="clients/web"
readonly OUT_DIR="assets/web"
readonly DEFAULT_PNPM_PACKAGE_MANAGER="pnpm@11.7.0"
readonly COREPACK_BUGGY_NODE_MAJOR=26

PNPM_CMD=()
BACKUP_DIR=""
OUT_DIR_TOUCHED=0
BUILD_OK=0

log() {
  echo "[build_web] $*"
}

fail() {
  echo "[build_web] $*" >&2
  exit 1
}

if [[ ! -d "$WEB_DIR" ]]; then
  fail "找不到 $WEB_DIR"
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

node_major_version() {
  if ! command -v node >/dev/null 2>&1; then
    printf '0'
    return
  fi
  node -p "Number(process.versions.node.split('.')[0]) || 0" 2>/dev/null || printf '0'
}

is_safe_out_dir() {
  case "$OUT_DIR" in
    ""|/|.|..|./|../) return 1;;
    *) return 0;;
  esac
}

run_pnpm() {
  "${PNPM_CMD[@]}" "$@"
}

pnpm_version() {
  pushd "$WEB_DIR" >/dev/null
  run_pnpm --version
  popd >/dev/null
}

try_existing_pnpm() {
  if ! command -v pnpm >/dev/null 2>&1; then
    return 1
  fi
  pushd "$WEB_DIR" >/dev/null
  if COREPACK_ENABLE_DOWNLOAD_PROMPT=0 pnpm --version >/dev/null 2>&1; then
    popd >/dev/null
    PNPM_CMD=(pnpm)
    return 0
  fi
  popd >/dev/null
  return 1
}

try_cached_corepack_pnpm() {
  local package_manager="$1"
  local version="${package_manager#pnpm@}"
  if [[ "$version" == "$package_manager" || -z "$version" || "$version" == */* ]]; then
    return 1
  fi

  local candidates=(
    "$HOME/.cache/node/corepack/v1/pnpm/$version/bin/pnpm.cjs"
    "$HOME/Library/Caches/node/corepack/v1/pnpm/$version/bin/pnpm.cjs"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" ]] || continue
    if node "$candidate" --version >/dev/null 2>&1; then
      PNPM_CMD=("$(command -v node)" "$candidate")
      return 0
    fi
  done
  return 1
}

try_corepack_pnpm() {
  local package_manager="$1"

  if ! command -v corepack >/dev/null 2>&1; then
    return 1
  fi

  if (( "$(node_major_version)" >= COREPACK_BUGGY_NODE_MAJOR )); then
    log "检测到 Node $(node -v)；跳过 Corepack 自动下载，避免已知的代理/undici 兼容问题"
    return 1
  fi

  log "未检测到可用 pnpm，使用 corepack 激活 $package_manager"
  if COREPACK_ENABLE_DOWNLOAD_PROMPT=0 corepack prepare "$package_manager" --activate >/dev/null; then
    PNPM_CMD=(corepack pnpm)
    return 0
  fi
  return 1
}

try_npm_exec_pnpm() {
  local package_manager="$1"

  if ! command -v npm >/dev/null 2>&1; then
    return 1
  fi

  log "改用 npm exec 临时运行 $package_manager"
  if npm exec --yes --package "$package_manager" -- pnpm --version >/dev/null 2>&1; then
    PNPM_CMD=(npm exec --yes --package "$package_manager" -- pnpm)
    return 0
  fi
  return 1
}

resolve_pnpm_command() {
  local package_manager
  package_manager="$(resolve_pnpm_package_manager)"

  if try_existing_pnpm; then
    log "使用 pnpm $(pnpm_version)"
    return
  fi
  if try_cached_corepack_pnpm "$package_manager"; then
    log "使用 Corepack 本地缓存 pnpm $(pnpm_version)"
    return
  fi
  if try_corepack_pnpm "$package_manager"; then
    log "使用 pnpm $(pnpm_version)"
    return
  fi
  if try_npm_exec_pnpm "$package_manager"; then
    log "使用 pnpm $(pnpm_version)"
    return
  fi

  fail "缺少可用 pnpm；请安装 $package_manager，或检查 npm/corepack 网络与代理配置"
}

install_web_dependencies() {
  pushd "$WEB_DIR" >/dev/null
  if [[ -f pnpm-lock.yaml ]]; then
    run_pnpm install --frozen-lockfile
  else
    run_pnpm install
  fi
  popd >/dev/null
}

backup_web_output() {
  BACKUP_DIR="$(mktemp -d)"
  mkdir -p "$BACKUP_DIR/out"
  if [[ -d "$OUT_DIR" ]]; then
    cp -a "$OUT_DIR/." "$BACKUP_DIR/out/"
  fi
}

restore_web_output() {
  if [[ "$OUT_DIR_TOUCHED" != "1" || "$BUILD_OK" == "1" || -z "$BACKUP_DIR" ]]; then
    return
  fi
  log "构建未完成，恢复原有 $OUT_DIR"
  rm -rf -- "$OUT_DIR"
  mkdir -p "$OUT_DIR"
  cp -a "$BACKUP_DIR/out/." "$OUT_DIR/" 2>/dev/null || true
}

cleanup() {
  local exit_code=$?
  restore_web_output
  if [[ -n "$BACKUP_DIR" ]]; then
    rm -rf -- "$BACKUP_DIR"
  fi
  exit "$exit_code"
}
trap cleanup EXIT

clean_web_output() {
  is_safe_out_dir || fail "拒绝清理可疑目录: '$OUT_DIR'"

  if [[ ! -d "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
  fi

  backup_web_output
  OUT_DIR_TOUCHED=1

  log "清理旧产物 → $OUT_DIR/{app.js,app.css,index.html,chunks,assets,*.map}"
  # 主入口 + sourcemap + 拆分子目录；public/ 内会被 vite 自动 copy 回来。
  rm -f -- \
    "$OUT_DIR/app.js" \
    "$OUT_DIR/app.css" \
    "$OUT_DIR/index.html" \
    "$OUT_DIR"/*.map
  rm -rf -- "$OUT_DIR/chunks" "$OUT_DIR/assets"
  mkdir -p "$OUT_DIR/chunks" "$OUT_DIR/assets"
}

build_web_client() {
  pushd "$WEB_DIR" >/dev/null
  run_pnpm build
  popd >/dev/null
}

# ---- 工具链 -----------------------------------------------------------------
resolve_pnpm_command
install_web_dependencies

# ---- 安全清理旧产物 ---------------------------------------------------------
# 依赖准备成功后再清理，避免 corepack/npm 网络失败时把可用旧产物删除。
clean_web_output

# ---- 构建 -------------------------------------------------------------------
build_web_client

# pubspec.yaml 声明了 assets/web/chunks/ 与 assets/web/assets/；两者被
# .gitignore 忽略且由 Vite 动态生成。构建失败或某些配置未产出对应目录时，
# 仍保持目录存在，避免 flutter analyze 出现 asset_directory_does_not_exist。
mkdir -p "$OUT_DIR/chunks" "$OUT_DIR/assets"
[[ -f "$OUT_DIR/chunks/.gitkeep" ]] || : > "$OUT_DIR/chunks/.gitkeep"
[[ -f "$OUT_DIR/assets/.gitkeep" ]] || : > "$OUT_DIR/assets/.gitkeep"

# ---- 校验关键产物已生成 -----------------------------------------------------
missing=()
for f in app.js app.css index.html; do
  [[ -s "$OUT_DIR/$f" ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  fail "构建失败：缺少产物 ${missing[*]}"
fi

BUILD_OK=1
log "OK → $OUT_DIR/{index.html,app.js,app.css}"

# ---- 跨 feature import 边界检查 --------------------------------------------
# 硬约束：违规即 fail。P0 plan-1/2/3/5 完成后过渡开关已移除。
log "跑 check_imports.dart"
if ! dart run scripts/check_imports.dart; then
  fail "FAIL：检测到跨 feature 深路径 import；请走对应 feature 的 barrel"
fi
