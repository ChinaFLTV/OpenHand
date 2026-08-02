import 'dart:io';

import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/platform_environment.dart';
import '../model/mcp_stdio_mirror_mode.dart';

/// 设置页「stdio 镜像源模式」实时同步过来的运行时变量。
/// `null` 表示未注入（首次启动 boot 阶段或未启用 MCP），按 auto 走 locale。
McpStdioMirrorMode? mcpStdioMirrorModeOverride;

/// 镜像源决策最终命中的来源。UI 用它渲染「当前生效」状态行。
enum McpMirrorEffectiveSource {
  /// 环境变量 OPENHAND_MCP_MIRROR=true/on/yes/enabled/1
  envOn,

  /// 环境变量 OPENHAND_MCP_MIRROR=false/off/no/disabled/0
  envOff,

  /// 设置项 = 强制开启
  settingForceOn,

  /// 设置项 = 强制关闭
  settingForceOff,

  /// 设置项 = auto，且 locale 是 zh*（注入）
  autoLocaleZh,

  /// 设置项 = auto，且 locale 不是 zh*（不注入）
  autoLocaleOther;

  bool get injects =>
      this == envOn || this == settingForceOn || this == autoLocaleZh;
}

/// 计算镜像源决策最终命中的来源，供 UI 与运行时注入逻辑共用。
McpMirrorEffectiveSource resolveMcpMirrorEffectiveSource() {
  final override = optionalBoolFromValue(
    platformEnvironmentValue('OPENHAND_MCP_MIRROR'),
  );
  if (override == true) {
    return McpMirrorEffectiveSource.envOn;
  }
  if (override == false) {
    return McpMirrorEffectiveSource.envOff;
  }
  switch (mcpStdioMirrorModeOverride) {
    case McpStdioMirrorMode.forceOn:
      return McpMirrorEffectiveSource.settingForceOn;
    case McpStdioMirrorMode.forceOff:
      return McpMirrorEffectiveSource.settingForceOff;
    case McpStdioMirrorMode.auto:
    case null:
      final locale = Platform.localeName.toLowerCase();
      return locale.startsWith('zh')
          ? McpMirrorEffectiveSource.autoLocaleZh
          : McpMirrorEffectiveSource.autoLocaleOther;
  }
}

bool shouldInjectMcpChinaMirror() {
  final source = resolveMcpMirrorEffectiveSource();
  return source.injects;
}
