#!/usr/bin/env bash
# 构建 OpenHand Web 通用消息平台前端，并把产物写入 assets/web/
# （由 vite.config.ts 的 build.outDir 直接指向，所以这里只负责
# install + 安全清理 + build + 校验）。CI 与开发者本地均可运行。
set -euo pipefail

cd "$(dirname "$0")/.."
readonly WEB_DIR="clients/web"
readonly OUT_DIR="assets/web"
readonly DEFAULT_PNPM_PACKAGE_MANAGER="pnpm@11.7.0"
readonly MIN_WEB_NODE_MAJOR=22
readonly COREPACK_BUGGY_NODE_MAJOR=26

PNPM_CMD=()
NODE_CMD=""
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

node_major_for() {
  local candidate="$1"
  "$candidate" -p "Number(process.versions.node.split('.')[0]) || 0" \
    2>/dev/null || printf '0'
}

resolve_node_command() {
  local candidates=()
  local current_node
  current_node="$(command -v node 2>/dev/null || true)"
  [[ -n "$current_node" ]] && candidates+=("$current_node")
  [[ -n "${NVM_BIN:-}" ]] && candidates+=("$NVM_BIN/node")
  candidates+=("$HOME/.nvm/versions/node"/v*/bin/node)

  local candidate
  local major
  local preferred=""
  local preferred_major=0
  local fallback=""
  local fallback_major=0
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    major="$(node_major_for "$candidate")"
    (( major >= MIN_WEB_NODE_MAJOR )) || continue
    if (( major < COREPACK_BUGGY_NODE_MAJOR && major > preferred_major )); then
      preferred="$candidate"
      preferred_major="$major"
    elif (( major > fallback_major )); then
      fallback="$candidate"
      fallback_major="$major"
    fi
  done

  NODE_CMD="${preferred:-$fallback}"
  if [[ -z "$NODE_CMD" ]]; then
    fail "Web 构建需要 Node.js ${MIN_WEB_NODE_MAJOR}+；请安装兼容版本"
  fi
  if [[ "$NODE_CMD" != "$current_node" ]]; then
    log "使用兼容 Node $($NODE_CMD -v) ($NODE_CMD)"
  fi
}

resolve_pnpm_package_manager() {
  "$NODE_CMD" - "$WEB_DIR/package.json" "$DEFAULT_PNPM_PACKAGE_MANAGER" <<'NODE'
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
  node_major_for "$NODE_CMD"
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
  local node_dir
  node_dir="$(dirname "$NODE_CMD")"
  pushd "$WEB_DIR" >/dev/null
  if PATH="$node_dir:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    pnpm --version >/dev/null 2>&1; then
    popd >/dev/null
    PNPM_CMD=(env "PATH=$node_dir:$PATH" pnpm)
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
    if "$NODE_CMD" "$candidate" --version >/dev/null 2>&1; then
      PNPM_CMD=("$NODE_CMD" "$candidate")
      return 0
    fi
  done
  return 1
}

try_corepack_pnpm() {
  local package_manager="$1"
  local node_dir
  node_dir="$(dirname "$NODE_CMD")"
  local corepack_command="$node_dir/corepack"

  if [[ ! -x "$corepack_command" ]]; then
    corepack_command="$(command -v corepack 2>/dev/null || true)"
    [[ -n "$corepack_command" ]] || return 1
  fi

  if (( "$(node_major_version)" >= COREPACK_BUGGY_NODE_MAJOR )); then
    log "检测到 Node $($NODE_CMD -v)；跳过 Corepack 自动下载，避免已知的代理/undici 兼容问题"
    return 1
  fi

  log "未检测到可用 pnpm，使用 corepack 激活 $package_manager"
  if PATH="$node_dir:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
      "$corepack_command" prepare "$package_manager" --activate >/dev/null \
    && PATH="$node_dir:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
      "$corepack_command" pnpm --version >/dev/null 2>&1; then
    PNPM_CMD=(env "PATH=$node_dir:$PATH" "$corepack_command" pnpm)
    return 0
  fi
  log "Corepack 已激活但 pnpm 无法启动，继续尝试其他工具链"
  return 1
}

try_npm_exec_pnpm() {
  local package_manager="$1"
  local node_dir
  node_dir="$(dirname "$NODE_CMD")"
  local npm_command="$node_dir/npm"

  if [[ ! -x "$npm_command" ]]; then
    npm_command="$(command -v npm 2>/dev/null || true)"
    [[ -n "$npm_command" ]] || return 1
  fi

  log "改用 npm exec 临时运行 $package_manager"
  if PATH="$node_dir:$PATH" "$npm_command" exec --yes \
      --package "$package_manager" -- pnpm --version >/dev/null 2>&1; then
    PNPM_CMD=(env "PATH=$node_dir:$PATH" "$npm_command" exec --yes \
      --package "$package_manager" -- pnpm)
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

  fail "缺少可用 pnpm；请安装 ${package_manager}，或检查 npm/corepack 网络与代理配置"
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

prepare_web_output() {
  is_safe_out_dir || fail "拒绝清理可疑目录: '$OUT_DIR'"

  if [[ ! -d "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
  fi

  backup_web_output
  OUT_DIR_TOUCHED=1
  log "由 Vite emptyOutDir 清理旧产物 → $OUT_DIR"
}

build_web_client() {
  (
    cd "$WEB_DIR"
    run_pnpm build
  )
}

# ---- 工具链 -----------------------------------------------------------------
resolve_node_command
resolve_pnpm_command
install_web_dependencies

# ---- 安全清理旧产物 ---------------------------------------------------------
# 依赖准备成功后再清理，避免 corepack/npm 网络失败时把可用旧产物删除。
prepare_web_output

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

# ---- 架构边界检查 -----------------------------------------------------------
# 架构边界属于硬约束，违规即终止构建。
log "跑 check_imports.dart"
if ! dart run scripts/check_imports.dart; then
  fail "架构检查失败：请修复上方边界违规"
fi

BUILD_OK=1
log "构建与架构检查通过 → $OUT_DIR/{index.html,app.js,app.css}"
