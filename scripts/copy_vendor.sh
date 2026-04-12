#!/bin/bash
# 2026-04-13: 复制 vendor 目录到应用包
# 此脚本用于在 macOS/Linux 构建后复制 ripgrep 等 vendor 依赖

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 检测目标平台
detect_platform() {
    local arch
    local os
    
    case "$(uname -s)" in
        Darwin)
            os="darwin"
            ;;
        Linux)
            os="linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            os="win32"
            ;;
        *)
            echo "Unsupported OS: $(uname -s)"
            exit 1
            ;;
    esac
    
    case "$(uname -m)" in
        arm64|aarch64)
            arch="arm64"
            ;;
        x86_64|amd64)
            arch="x64"
            ;;
        *)
            echo "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    
    echo "${arch}-${os}"
}

# macOS: 复制到 .app/Contents/Resources/vendor
copy_vendor_macos() {
    local app_path="$1"
    local platform="$2"
    
    if [[ ! -d "$app_path" ]]; then
        echo "Error: App bundle not found: $app_path"
        exit 1
    fi
    
    local resources_dir="$app_path/Contents/Resources"
    local vendor_dest="$resources_dir/vendor/ripgrep/$platform"
    
    echo "Copying vendor files to $vendor_dest"
    mkdir -p "$vendor_dest"
    
    # 复制 ripgrep 二进制
    local rg_src="$PROJECT_ROOT/vendor/ripgrep/$platform/rg"
    if [[ -f "$rg_src" ]]; then
        cp "$rg_src" "$vendor_dest/"
        chmod +x "$vendor_dest/rg"
        echo "Copied: $rg_src -> $vendor_dest/rg"
    else
        echo "Warning: ripgrep binary not found: $rg_src"
    fi
    
    # 复制许可证
    local license_src="$PROJECT_ROOT/vendor/ripgrep/COPYING"
    if [[ -f "$license_src" ]]; then
        cp "$license_src" "$resources_dir/vendor/ripgrep/"
        echo "Copied: $license_src"
    fi
}

# Linux: 复制到可执行文件同级目录
copy_vendor_linux() {
    local app_dir="$1"
    local platform="$2"
    
    if [[ ! -d "$app_dir" ]]; then
        echo "Error: App directory not found: $app_dir"
        exit 1
    fi
    
    local vendor_dest="$app_dir/vendor/ripgrep/$platform"
    
    echo "Copying vendor files to $vendor_dest"
    mkdir -p "$vendor_dest"
    
    local rg_src="$PROJECT_ROOT/vendor/ripgrep/$platform/rg"
    if [[ -f "$rg_src" ]]; then
        cp "$rg_src" "$vendor_dest/"
        chmod +x "$vendor_dest/rg"
        echo "Copied: $rg_src -> $vendor_dest/rg"
    else
        echo "Warning: ripgrep binary not found: $rg_src"
    fi
    
    local license_src="$PROJECT_ROOT/vendor/ripgrep/COPYING"
    if [[ -f "$license_src" ]]; then
        mkdir -p "$app_dir/vendor/ripgrep"
        cp "$license_src" "$app_dir/vendor/ripgrep/"
        echo "Copied: $license_src"
    fi
}

# 主逻辑
main() {
    local target_path="$1"
    local platform="${2:-$(detect_platform)}"
    
    if [[ -z "$target_path" ]]; then
        echo "Usage: $0 <app_path> [platform]"
        echo ""
        echo "Examples:"
        echo "  macOS:  $0 build/macos/Build/Products/Release/OpenHand.app"
        echo "  Linux:  $0 build/linux/x64/release/bundle"
        echo ""
        echo "Detected platform: $platform"
        exit 1
    fi
    
    echo "Platform: $platform"
    echo "Target: $target_path"
    echo ""
    
    case "$platform" in
        *-darwin)
            copy_vendor_macos "$target_path" "$platform"
            ;;
        *-linux)
            copy_vendor_linux "$target_path" "$platform"
            ;;
        *)
            echo "Unsupported platform: $platform"
            exit 1
            ;;
    esac
    
    echo ""
    echo "Done!"
}

main "$@"
