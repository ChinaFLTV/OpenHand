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
    this.extraFields = const <String, Object?>{},
  });

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
  final Map<String, Object?> extraFields;

  String get initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'M';
    }
    return trimmed.substring(0, 1).toUpperCase();
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
      extraFields: extraFields ?? this.extraFields,
    );
  }
}
