/// stdio MCP 包管理器镜像源模式。决定 npx / npm / uv / pip 这类工具
/// 是否走国内镜像（npmmirror / 清华 PyPI），独立于系统 locale。
///
///   - [auto]: 看 `Platform.localeName`，zh* 自动开镜像，其余用默认 registry。
///   - [forceOn]: 强制注入国内镜像（无视 locale）。
///   - [forceOff]: 强制不注入（走 npm 全球默认 registry / 全球 PyPI）。
///
/// 环境变量 `OPENHAND_MCP_MIRROR=on/off` 可在运行时再覆盖一次（最高优先级），
/// 方便临时切换不重启应用。
enum McpStdioMirrorMode {
  auto('auto'),
  forceOn('force_on'),
  forceOff('force_off');

  const McpStdioMirrorMode(this.storageValue);

  final String storageValue;

  static McpStdioMirrorMode fromStorage(String? raw) {
    final v = raw?.trim().toLowerCase();
    for (final mode in McpStdioMirrorMode.values) {
      if (mode.storageValue == v) return mode;
    }
    return McpStdioMirrorMode.auto;
  }
}
