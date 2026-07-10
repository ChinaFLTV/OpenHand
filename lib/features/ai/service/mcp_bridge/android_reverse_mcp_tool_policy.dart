import '../../../../shared/util/input_value_parsing.dart';
import '../runtime/ai_tool_runtime_service.dart';

class AndroidReverseMcpToolPolicy {
  const AndroidReverseMcpToolPolicy._();

  static Set<String> forceVisibleToolNames(AiResolvedToolCatalog catalog) {
    final names = <String>{};
    for (final entry in catalog.toolsByName.entries) {
      if (_shouldForceVisibleTool(entry.value, catalogName: entry.key)) {
        names.add(entry.key);
      }
    }
    return names;
  }

  static bool _shouldForceVisibleTool(
    AiResolvedTool tool, {
    String? catalogName,
  }) {
    if (tool.source != AiRuntimeToolSource.mcp) return false;

    final server = tool.mcpServer;
    final mcpTool = tool.mcpTool;
    final identity = _joinParts(<Object?>[
      catalogName,
      tool.name,
      tool.definition.name,
      server?.name,
      server?.summary,
      server?.command,
      if (server != null) ...server.args,
      server?.url,
      mcpTool?.id,
      mcpTool?.name,
    ]);
    final descriptive = _joinParts(<Object?>[
      identity,
      tool.definition.description,
      mcpTool?.description,
      mcpTool?.outputDescription,
      mcpTool?.annotations,
      mcpTool?.execution,
      mcpTool?.rawMetadata,
    ]);
    final launchIdentity = _joinParts(<Object?>[
      server?.command,
      if (server != null) ...server.args,
      server?.url,
    ]);

    if (_hasStrongLaunchSignal(launchIdentity)) return true;
    if (_hasAndroidReverseSignal(identity) && _hasOperationSignal(identity)) {
      return true;
    }
    return _hasAndroidReverseSignal(identity) &&
        _hasOperationSignal(descriptive);
  }

  static bool _hasStrongLaunchSignal(String value) {
    return _containsAny(value, const <String>[
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
    return _containsAny(value, const <String>[
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
    return _containsAny(value, const <String>[
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

  static bool _containsAny(String value, Iterable<String> needles) {
    for (final needle in needles) {
      if (value.contains(needle)) return true;
    }
    return false;
  }

  static String _joinParts(Iterable<Object?> parts) {
    return trimmedNonEmptyStrings(parts).join('\n').toLowerCase();
  }
}
