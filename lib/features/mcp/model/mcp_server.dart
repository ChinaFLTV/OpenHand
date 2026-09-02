import 'package:characters/characters.dart';

import '../../../shared/util/byte_size_format.dart';

const int kMcpMaxServerCount = 256;
const int kMcpMaxServerNameCharacters = 160;
const int kMcpMaxUrlCharacters = 8 * kBytesPerKiB;
const int kMcpMaxCommandCharacters = 16 * kBytesPerKiB;
const int kMcpMaxArgumentCount = 256;
const int kMcpMaxArgumentCharacters = 32 * kBytesPerKiB;
const int kMcpMaxHeaderCount = 128;
const int kMcpMaxHeaderNameCharacters = 256;
const int kMcpMaxHeaderValueCharacters = 16 * kBytesPerKiB;
const int kMcpMaxEnvironmentCount = 256;
const int kMcpMaxEnvironmentNameCharacters = 256;
const int kMcpMaxEnvironmentValueCharacters = 64 * kBytesPerKiB;
const int kMcpMaxVisibleTemplateCount = 128;
const int kMcpMaxTemplateIdCharacters = 256;

enum McpServerType {
  streamableHttp('streamable_http'),
  sse('sse'),
  stdio('stdio');

  const McpServerType(this.storageValue);

  final String storageValue;

  String get transportValue {
    return switch (this) {
      McpServerType.streamableHttp => 'http',
      McpServerType.sse => 'sse',
      McpServerType.stdio => 'stdio',
    };
  }

  static McpServerType? fromStorage(String? value) {
    final normalizedValue = value?.trim().toLowerCase() ?? '';
    return switch (normalizedValue) {
      'streamable_http' ||
      'streamable-http' ||
      'streamablehttp' ||
      'http' => McpServerType.streamableHttp,
      'sse' => McpServerType.sse,
      'stdio' => McpServerType.stdio,
      _ => null,
    };
  }
}

const Object _mcpVisibleTemplateIdsUnchanged = Object();

class McpServer {
  const McpServer({
    required this.name,
    required this.type,
    required this.enabled,
    this.probeEnabled = true,
    this.url = '',
    this.command = '',
    this.args = const <String>[],
    this.headers = const <String, String>{},
    this.environment = const <String, String>{},
    this.visibleTemplateIds,
    this.extraFields = const <String, Object?>{},
  });

  static const String webReverseExpertTemplateId = 'web_reverse_expert';
  static const String androidReverseExpertTemplateId = 'android_reverse_expert';

  static const Map<String, Set<String>> _builtInVisibleTemplateIds =
      <String, Set<String>>{
        'Web Reverse CDP MCP': <String>{webReverseExpertTemplateId},
        'Playwright MCP': <String>{webReverseExpertTemplateId},
        'JS Reverse MCP': <String>{webReverseExpertTemplateId},
        'Android ADB MCP': <String>{androidReverseExpertTemplateId},
        'Android Frida MCP': <String>{androidReverseExpertTemplateId},
        'Anything Analyzer MCP': <String>{androidReverseExpertTemplateId},
      };

  final String name;
  final McpServerType type;

  /// 是否启用此 MCP 服务（控制是否注入到线程 Prompt、是否参与工具调用）。
  final bool enabled;

  /// 是否参与自动探测（健康检查 + Tool 扫描）。独立于 enabled：
  /// 服务可以启用但不探测（手动管理），也可以禁用时自动跟随禁用探测。
  final bool probeEnabled;

  final String url;
  final String command;
  final List<String> args;
  final Map<String, String> headers;
  final Map<String, String> environment;

  /// null 表示对所有线程模板可见；非 null 时至少包含一个模板。
  final Set<String>? visibleTemplateIds;
  final Map<String, Object?> extraFields;

  static Set<String>? defaultVisibleTemplateIdsForName(String serverName) {
    return _builtInVisibleTemplateIds[serverName];
  }

  bool isVisibleToTemplate(String templateId) {
    final visibleIds = visibleTemplateIds;
    return visibleIds == null || visibleIds.contains(templateId.trim());
  }

  McpServer withVisibleTemplate(String templateId) {
    final normalizedTemplateId = templateId.trim();
    final visibleIds = visibleTemplateIds;
    if (normalizedTemplateId.isEmpty ||
        visibleIds == null ||
        visibleIds.contains(normalizedTemplateId)) {
      return this;
    }
    return copyWith(
      visibleTemplateIds: Set<String>.unmodifiable(<String>{
        ...visibleIds,
        normalizedTemplateId,
      }),
    );
  }

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'M';
    }
    return trimmed.characters.first.toUpperCase();
  }

  String get summary {
    return switch (type) {
      McpServerType.streamableHttp || McpServerType.sse => url.trim(),
      McpServerType.stdio => <String>[
        command.trim(),
        ...args,
      ].where((item) => item.isNotEmpty).join(' '),
    };
  }

  McpServer copyWith({
    String? name,
    McpServerType? type,
    bool? enabled,
    bool? probeEnabled,
    String? url,
    String? command,
    List<String>? args,
    Map<String, String>? headers,
    Map<String, String>? environment,
    Object? visibleTemplateIds = _mcpVisibleTemplateIdsUnchanged,
    Map<String, Object?>? extraFields,
  }) {
    return McpServer(
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      probeEnabled: probeEnabled ?? this.probeEnabled,
      url: url ?? this.url,
      command: command ?? this.command,
      args: args ?? this.args,
      headers: headers ?? this.headers,
      environment: environment ?? this.environment,
      visibleTemplateIds:
          identical(visibleTemplateIds, _mcpVisibleTemplateIdsUnchanged)
          ? this.visibleTemplateIds
          : visibleTemplateIds as Set<String>?,
      extraFields: extraFields ?? this.extraFields,
    );
  }
}
