#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSET_ROOT="$PROJECT_ROOT/assets/ai_jungler"
SELECTION="${1:-all}"

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

verify_platform() {
  local platform executable binary manifest expected actual declared_platform declared_executable
  platform="$1"
  executable="ai_jungler"
  if [[ "$platform" == windows-* ]]; then
    executable="ai_jungler.exe"
  fi
  binary="$ASSET_ROOT/$platform/$executable"
  manifest="$ASSET_ROOT/$platform/manifest.json"
  command -v jq >/dev/null 2>&1 || { echo "当前环境缺少 jq。" >&2; return 1; }
  [[ -f "$binary" ]] || { echo "缺少二进制：$binary" >&2; return 1; }
  [[ -f "$manifest" ]] || { echo "缺少清单：$manifest" >&2; return 1; }
  declared_platform="$(jq -r '.platform // empty' "$manifest")"
  declared_executable="$(jq -r '.executable // empty' "$manifest")"
  expected="$(jq -r '.sha256 // empty' "$manifest")"
  actual="$(sha256_file "$binary")"
  [[ "$declared_platform" == "$platform" ]] || { echo "清单平台不匹配：$platform" >&2; return 1; }
  [[ "$declared_executable" == "$executable" ]] || { echo "清单文件名不匹配：$platform" >&2; return 1; }
  [[ ${#expected} -eq 64 && "$expected" == "$actual" ]] || { echo "二进制摘要不匹配：$platform" >&2; return 1; }
  echo "校验通过：$platform"
}

verify_root_manifest() {
  local manifest platform
  manifest="$ASSET_ROOT/manifest.json"
  command -v jq >/dev/null 2>&1 || { echo "当前环境缺少 jq。" >&2; return 1; }
  [[ -f "$manifest" ]] || { echo "缺少汇总清单：$manifest" >&2; return 1; }
  [[ "$(jq -r '.engine // empty' "$manifest")" == "ai_jungler" ]] || {
    echo "汇总清单引擎名称无效。" >&2
    return 1
  }
  [[ "$(jq '.supportedPlatforms | length' "$manifest")" -eq 6 &&
     "$(jq '.bundledPlatforms | length' "$manifest")" -eq 6 ]] || {
    echo "汇总清单的平台数量无效。" >&2
    return 1
  }
  for platform in darwin-arm64 darwin-x64 windows-arm64 windows-x64 linux-arm64 linux-x64; do
    jq -e --arg platform "$platform" '.supportedPlatforms | index($platform) != null' "$manifest" >/dev/null || {
      echo "汇总清单缺少支持平台：$platform" >&2
      return 1
    }
    jq -e --arg platform "$platform" '.bundledPlatforms | index($platform) != null' "$manifest" >/dev/null || {
      echo "汇总清单缺少内置平台：$platform" >&2
      return 1
    }
  done
}

if [[ "$SELECTION" == "all" ]]; then
  for platform in darwin-arm64 darwin-x64 windows-arm64 windows-x64 linux-arm64 linux-x64; do
    verify_platform "$platform"
  done
  verify_root_manifest
else
  verify_platform "$SELECTION"
fi
