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
    this.url = '',
    this.command = '',
    this.args = const <String>[],
    this.headers = const <String, String>{},
  });

  final String name;
  final McpServerType type;
  final bool enabled;
  final String url;
  final String command;
  final List<String> args;
  final Map<String, String> headers;

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
      McpServerType.stdio => [
        command.trim(),
        ...args.map((item) => item.trim()).where((item) => item.isNotEmpty),
      ].where((item) => item.isNotEmpty).join(' '),
    };
  }

  McpServer copyWith({
    String? name,
    McpServerType? type,
    bool? enabled,
    String? url,
    String? command,
    List<String>? args,
    Map<String, String>? headers,
  }) {
    return McpServer(
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      url: url ?? this.url,
      command: command ?? this.command,
      args: args ?? this.args,
      headers: headers ?? this.headers,
    );
  }
}
