import '../runtime/ai_tool_runtime_service.dart';
import 'mcp_reverse_tool_policy_utils.dart';

class AndroidReverseMcpToolPolicy {
  const AndroidReverseMcpToolPolicy._();

  static Set<String> forceVisibleToolNames(AiResolvedToolCatalog catalog) {
    return forceVisibleMcpToolNames(
      catalog,
      (tool, catalogName) =>
          _shouldForceVisibleTool(tool, catalogName: catalogName),
    );
  }

  static bool _shouldForceVisibleTool(
    AiResolvedTool tool, {
    required String catalogName,
  }) {
    if (tool.source != AiRuntimeToolSource.mcp) return false;

    final text = mcpReverseToolSearchText(tool, catalogName: catalogName);

    if (_hasStrongLaunchSignal(text.launchIdentity)) return true;
    if (_hasAndroidReverseSignal(text.identity) &&
        _hasOperationSignal(text.identity)) {
      return true;
    }
    return _hasAndroidReverseSignal(text.identity) &&
        _hasOperationSignal(text.descriptive);
  }

  static bool _hasStrongLaunchSignal(String value) {
    return mcpToolSearchTextContainsAny(value, const <String>[
      'android-adb',
      'android_adb',
      'android mcp',
      'adb-mcp',
      'adb_mcp',
      'frida-mcp',
      'frida_mcp',
      'ida-pro-mcp',
      'idapro-mcp',
      'apktool',
      'jadx',
      'radare2',
      'anything-analyzer',
    ]);
  }

  static bool _hasAndroidReverseSignal(String value) {
    return mcpToolSearchTextContainsAny(value, const <String>[
      'android',
      'adb',
      'apk',
      'aapt',
      'apksigner',
      'apktool',
      'jadx',
      'frida',
      'objection',
      'ida',
      'ida pro',
      'radare',
      'radare2',
      ' r2 ',
      'mitm',
      'mitmproxy',
      'logcat',
      'emulator',
      'flutter',
      'dart',
      'blutter',
      'doldrums',
      'anything-analyzer',
    ]);
  }

  static bool _hasOperationSignal(String value) {
    return mcpToolSearchTextContainsAny(value, const <String>[
      'activity',
      'analyze',
      'attach',
      'call',
      'cert',
      'command',
      'decompile',
      'device',
      'dump',
      'execute',
      'file',
      'forward',
      'get',
      'hook',
      'install',
      'launch',
      'list',
      'log',
      'logcat',
      'package',
      'pid',
      'process',
      'proxy',
      'pull',
      'push',
      'read',
      'record',
      'reverse',
      'run',
      'screen',
      'screenshot',
      'shell',
      'spawn',
      'strings',
      'trace',
      'uninstall',
    ]);
  }
}
