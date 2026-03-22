enum McpServerType {
  streamableHttp('streamable_http'),
  sse('sse'),
  stdio('stdio');

  const McpServerType(this.storageValue);

  final String storageValue;

  static McpServerType? fromStorage(String? value) {
    for (final item in McpServerType.values) {
      if (item.storageValue == value) {
        return item;
      }
    }
    return null;
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
  });

  final String name;
  final McpServerType type;
  final bool enabled;
  final String url;
  final String command;
  final List<String> args;

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
  }) {
    return McpServer(
      name: name ?? this.name,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      url: url ?? this.url,
      command: command ?? this.command,
      args: args ?? this.args,
    );
  }
}
