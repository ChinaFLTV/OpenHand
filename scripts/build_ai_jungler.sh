#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE_ROOT="$PROJECT_ROOT/native/ai_jungler"
ASSET_ROOT="$PROJECT_ROOT/assets/ai_jungler"
SELECTION="${1:-host}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "当前环境缺少 SHA-256 工具。" >&2
    return 1
  fi
}

platform_target() {
  case "$1" in
    darwin-arm64) echo "aarch64-apple-darwin" ;;
    darwin-x64) echo "x86_64-apple-darwin" ;;
    windows-arm64) echo "aarch64-pc-windows-msvc" ;;
    windows-x64) echo "x86_64-pc-windows-msvc" ;;
    linux-arm64) echo "aarch64-unknown-linux-gnu" ;;
    linux-x64) echo "x86_64-unknown-linux-gnu" ;;
    *) echo "不支持的平台：$1" >&2; return 1 ;;
  esac
}

host_platform() {
  local system machine
  system="$(uname -s)"
  machine="$(uname -m)"
  case "$system-$machine" in
    Darwin-arm64) echo "darwin-arm64" ;;
    Darwin-x86_64) echo "darwin-x64" ;;
    Linux-aarch64|Linux-arm64) echo "linux-arm64" ;;
    Linux-x86_64) echo "linux-x64" ;;
    MINGW*-aarch64|MSYS*-aarch64) echo "windows-arm64" ;;
    MINGW*-x86_64|MSYS*-x86_64) echo "windows-x64" ;;
    *) echo "无法识别当前平台：$system $machine" >&2; return 1 ;;
  esac
}

build_rust_binary() {
  local platform target host
  platform="$1"
  target="$2"
  host="$(host_platform)"
  if [[ "$platform" == windows-* && "$host" != "$platform" ]]; then
    command -v cargo-xwin >/dev/null 2>&1 || {
      echo "交叉构建 $platform 需要 cargo-xwin。" >&2
      return 1
    }
    cargo xwin build --cross-compiler clang --manifest-path "$ENGINE_ROOT/Cargo.toml" \
      --package hunt-daemon --release --locked --target "$target"
  elif [[ "$platform" == linux-* && "$host" != "$platform" ]]; then
    command -v cargo-zigbuild >/dev/null 2>&1 || {
      echo "交叉构建 $platform 需要 cargo-zigbuild。" >&2
      return 1
    }
    cargo zigbuild --manifest-path "$ENGINE_ROOT/Cargo.toml" \
      --package hunt-daemon --release --locked --target "$target"
  else
    cargo build --manifest-path "$ENGINE_ROOT/Cargo.toml" \
      --package hunt-daemon --release --locked --target "$target"
  fi
}

build_platform() {
  local platform target source destination executable checksum manifest
  platform="$1"
  target="$(platform_target "$platform")"
  executable="ai_jungler"
  if [[ "$platform" == windows-* ]]; then
    executable="ai_jungler.exe"
  fi
  if ! rustup target list --installed | grep -Fxq "$target"; then
    echo "缺少 Rust target：$target" >&2
    return 1
  fi
  build_rust_binary "$platform" "$target"
  source="$ENGINE_ROOT/target/$target/release/$executable"
  destination="$ASSET_ROOT/$platform/$executable"
  mkdir -p "$(dirname "$destination")"
  install -m 700 "$source" "$destination"
  rm -f "$ASSET_ROOT/$platform/README.txt"
  checksum="$(sha256_file "$destination")"
  manifest="$ASSET_ROOT/$platform/manifest.json"
  printf '{\n  "engine": "ai_jungler",\n  "version": "0.1.0",\n  "platform": "%s",\n  "executable": "%s",\n  "sha256": "%s"\n}\n' \
    "$platform" "$executable" "$checksum" >"$manifest"
  echo "已生成：$destination"
}

case "$SELECTION" in
  host)
    build_platform "$(host_platform)"
    ;;
  all)
    for platform in \
      darwin-arm64 darwin-x64 windows-arm64 windows-x64 linux-arm64 linux-x64
    do
      build_platform "$platform"
    done
    ;;
  *)
    build_platform "$SELECTION"
    ;;
esac
