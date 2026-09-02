import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/silent_log.dart';
import '../../../app/support/url_validation.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
import '../../../shared/util/text_clip.dart';
import '../../../shared/util/user_failure_message.dart';
import '../model/mcp_http_headers.dart';
import '../model/mcp_server.dart';

enum McpPersistenceIssueKind { loadFailed, invalidContent, saveFailed }

class McpPersistenceIssue {
  const McpPersistenceIssue({
    required this.kind,
    required this.filePath,
    this.detail,
  });

  final McpPersistenceIssueKind kind;
  final String filePath;
  final String? detail;
}

class McpLoadResult {
  const McpLoadResult({
    required this.servers,
    required this.canPersist,
    this.issue,
  });

  final List<McpServer> servers;
  final bool canPersist;
  final McpPersistenceIssue? issue;
}

class McpStore {
  McpStore({String? serversFilePath})
    : _serversFilePath =
          serversFilePath ?? OpenHandPaths.defaultMcpServersFilePath();

  static const String _serversRootKey = 'mcpServers';
  static const int _maxServersFileBytes = 4 * kBytesPerMiB;
  static const Set<String> _serverFields = <String>{
    'enabled',
    'probeEnabled',
    'type',
    'transport',
    'url',
    'command',
    'args',
    'headers',
    'env',
    'visibleTemplateIds',
  };

  final String _serversFilePath;
  Map<String, Object?> _rootExtraFields = const <String, Object?>{};
  String? _expectedContent;
  bool _hasLoadedSnapshot = false;
  bool _canPersist = false;

  String get serversFilePath => _serversFilePath;
  String get storageDirectoryPath => p.dirname(_serversFilePath);

  Future<McpLoadResult> load() async {
    _canPersist = false;
    final targetFile = File(_serversFilePath);
    try {
      await recoverAtomicWriteBackupIfNeeded(targetFile);
      if (!await regularFileExistsBounded(targetFile)) {
        _acceptSnapshot(
          expectedContent: null,
          rootExtraFields: const <String, Object?>{},
        );
        return const McpLoadResult(servers: <McpServer>[], canPersist: true);
      }
      final raw = await readBoundedFileString(
        targetFile,
        maxBytes: _maxServersFileBytes,
      );
      try {
        final parsed = _parseRoot(jsonDecode(raw));
        _acceptSnapshot(
          expectedContent: raw,
          rootExtraFields: parsed.rootExtraFields,
        );
        return McpLoadResult(servers: parsed.servers, canPersist: true);
      } catch (error, stack) {
        silentLog('mcp_store', '解析 MCP 配置', error, stack);
        return _failedLoad(McpPersistenceIssueKind.invalidContent, error);
      }
    } catch (error, stack) {
      silentLog('mcp_store', '加载 MCP 配置', error, stack);
      return _failedLoad(McpPersistenceIssueKind.loadFailed, error);
    }
  }

  Future<void> save(List<McpServer> servers) async {
    if (!_hasLoadedSnapshot || !_canPersist) {
      throw StateError('MCP 配置缺少可信快照。');
    }
    await _verifySourceUnchanged();
    final content = _encode(servers);
    if (utf8ByteLength(content) > _maxServersFileBytes) {
      throw const FileSystemException('MCP 配置超过大小上限。');
    }
    final targetFile = File(_serversFilePath);
    await writeFileAtomically(targetFile, content);
    _expectedContent = content;
  }

  _ParsedRoot _parseRoot(Object? decoded) {
    validateCanonicalJsonSubset(
      decoded,
      decoded,
      path: 'MCP 配置',
      maxDepth: 48,
      maxContainerItems: 4096,
      maxTotalNodes: 65536,
    );
    final root = _jsonObject(decoded, 'MCP 根对象');
    final rawServers = root[_serversRootKey];
    if (rawServers is! Map) {
      throw const FormatException('mcpServers 必须为对象。');
    }
    if (rawServers.length > kMcpMaxServerCount) {
      throw const FormatException('MCP 服务数量超过安全上限。');
    }
    final servers = <McpServer>[];
    final normalizedNames = <String>{};
    for (final entry in rawServers.entries) {
      if (entry.key is! String) {
        throw const FormatException('MCP 服务名称必须为文本。');
      }
      final server = _parseServer(entry.key as String, entry.value);
      if (!normalizedNames.add(server.name.toLowerCase())) {
        throw FormatException('MCP 服务名称重复：${server.name}');
      }
      servers.add(server);
    }
    return _ParsedRoot(
      servers: List<McpServer>.unmodifiable(servers),
      rootExtraFields: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in root.entries)
          if (entry.key != _serversRootKey) entry.key: entry.value,
      }),
    );
  }

  McpServer _parseServer(String rawName, Object? rawValue) {
    final name = rawName.trim();
    if (name.isEmpty ||
        name != rawName ||
        name.length > kMcpMaxServerNameCharacters) {
      throw const FormatException('MCP 服务名称无效。');
    }
    final source = _jsonObject(rawValue, 'MCP 服务 $name');
    final url = _optionalText(source, 'url');
    final command = _optionalText(source, 'command');
    final type = _resolveType(source, url: url, command: command);
    final server = McpServer(
      name: name,
      type: type,
      enabled: _optionalBool(source, 'enabled', fallback: true),
      probeEnabled: _optionalBool(source, 'probeEnabled', fallback: true),
      url: url,
      command: command,
      args: _stringList(source, 'args'),
      headers: _headers(source['headers']),
      environment: _environment(source['env']),
      visibleTemplateIds: _visibleTemplateIds(source, name),
      extraFields: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in source.entries)
          if (!_serverFields.contains(entry.key)) entry.key: entry.value,
      }),
    );
    _validateServer(server);
    return server;
  }

  McpServerType _resolveType(
    Map<String, Object?> source, {
    required String url,
    required String command,
  }) {
    McpServerType? parseExplicit(String key) {
      if (!source.containsKey(key)) return null;
      final raw = source[key];
      if (raw is! String) {
        throw FormatException('MCP $key 必须为文本。');
      }
      final parsed = McpServerType.fromStorage(raw);
      if (parsed == null) throw FormatException('不支持的 MCP $key：$raw');
      return parsed;
    }

    final declaredType = parseExplicit('type');
    final declaredTransport = parseExplicit('transport');
    if (declaredType != null &&
        declaredTransport != null &&
        declaredType != declaredTransport) {
      throw const FormatException('MCP type 与 transport 冲突。');
    }
    final explicit = declaredType ?? declaredTransport;
    if (explicit != null) return explicit;
    final hasCommand = command.trim().isNotEmpty;
    final hasUrl = isValidHttpUrl(url);
    if (hasCommand == hasUrl) {
      throw const FormatException('无法推断 MCP 传输类型。');
    }
    return hasCommand ? McpServerType.stdio : McpServerType.streamableHttp;
  }

  String _encode(List<McpServer> servers) {
    if (servers.length > kMcpMaxServerCount) {
      throw const FormatException('MCP 服务数量超过安全上限。');
    }
    final names = <String>{};
    final entries = <String, Object?>{};
    for (final server in servers) {
      _validateServer(server);
      if (!names.add(server.name.toLowerCase())) {
        throw FormatException('MCP 服务重复：${server.name}');
      }
      entries[server.name] = <String, Object?>{
        ...server.extraFields,
        'enabled': server.enabled,
        'probeEnabled': server.probeEnabled,
        'type': server.type.storageValue,
        'transport': server.type.transportValue,
        if (server.url.isNotEmpty) 'url': server.url,
        if (server.command.isNotEmpty) 'command': server.command,
        if (server.type == McpServerType.stdio || server.args.isNotEmpty)
          'args': List<String>.from(server.args),
        if (server.headers.isNotEmpty)
          'headers': Map<String, String>.from(server.headers),
        if (server.environment.isNotEmpty)
          'env': Map<String, String>.from(server.environment),
        'visibleTemplateIds': server.visibleTemplateIds == null
            ? null
            : (server.visibleTemplateIds!.toList(growable: false)..sort()),
      };
    }
    return prettyPrintJson(<String, Object?>{
      ..._rootExtraFields,
      _serversRootKey: entries,
    });
  }

  void _validateServer(McpServer server) {
    if (server.name.isEmpty ||
        server.name.trim() != server.name ||
        server.name.length > kMcpMaxServerNameCharacters) {
      throw const FormatException('MCP 服务名称无效。');
    }
    if (server.url != server.url.trim() ||
        server.url.length > kMcpMaxUrlCharacters ||
        server.command != server.command.trim() ||
        server.command.length > kMcpMaxCommandCharacters ||
        server.command.contains('\u0000')) {
      throw FormatException('MCP 服务 ${server.name} 的连接配置无效。');
    }
    if (server.type == McpServerType.stdio) {
      if (server.command.isEmpty) {
        throw FormatException('MCP stdio 服务 ${server.name} 缺少 command。');
      }
    } else if (!isValidHttpUrl(server.url)) {
      throw FormatException('MCP HTTP 服务 ${server.name} 的 URL 无效。');
    }
    if (server.args.length > kMcpMaxArgumentCount ||
        server.args.any(
          (argument) =>
              argument.length > kMcpMaxArgumentCharacters ||
              argument.contains('\u0000'),
        )) {
      throw FormatException('MCP 服务 ${server.name} 的参数配置无效。');
    }
    _validateHeaders(server.headers);
    _validateEnvironment(server.environment);
    _validateVisibleTemplateIds(server.visibleTemplateIds);
  }

  Set<String>? _visibleTemplateIds(
    Map<String, Object?> source,
    String serverName,
  ) {
    if (!source.containsKey('visibleTemplateIds')) {
      return McpServer.defaultVisibleTemplateIdsForName(serverName);
    }
    final raw = source['visibleTemplateIds'];
    if (raw == null) return null;
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > kMcpMaxVisibleTemplateCount ||
        raw.any((item) => item is! String)) {
      throw const FormatException('MCP visibleTemplateIds 必须是非空字符串数组。');
    }
    final values = <String>{};
    for (final item in raw.cast<String>()) {
      if (item.isEmpty ||
          item.trim() != item ||
          item.length > kMcpMaxTemplateIdCharacters ||
          !values.add(item)) {
        throw const FormatException('MCP visibleTemplateIds 包含无效或重复项。');
      }
    }
    return Set<String>.unmodifiable(values);
  }

  void _validateVisibleTemplateIds(Set<String>? visibleTemplateIds) {
    if (visibleTemplateIds == null) return;
    if (visibleTemplateIds.isEmpty) {
      throw const FormatException('显式模板可见性配置不能为空。');
    }
    if (visibleTemplateIds.length > kMcpMaxVisibleTemplateCount) {
      throw const FormatException('模板可见性配置数量超过安全上限。');
    }
    for (final templateId in visibleTemplateIds) {
      if (templateId.isEmpty ||
          templateId.trim() != templateId ||
          templateId.length > kMcpMaxTemplateIdCharacters) {
        throw const FormatException('模板可见性配置不能包含空值或首尾空白。');
      }
    }
  }

  Map<String, String> _headers(Object? raw) {
    if (raw == null) return const <String, String>{};
    final values = _stringMap(
      raw,
      'MCP headers 字段',
      maxEntries: kMcpMaxHeaderCount,
    );
    _validateHeaders(values);
    return Map<String, String>.unmodifiable(values);
  }

  void _validateHeaders(Map<String, String> headers) {
    if (headers.length > kMcpMaxHeaderCount) {
      throw const FormatException('MCP 请求头数量超过安全上限。');
    }
    for (final entry in headers.entries) {
      if (entry.key != entry.key.trim() ||
          entry.value != entry.value.trim() ||
          entry.key.length > kMcpMaxHeaderNameCharacters ||
          entry.value.length > kMcpMaxHeaderValueCharacters ||
          !isValidMcpHttpHeader(entry.key, entry.value)) {
        throw FormatException('无效的 MCP 请求头：${entry.key}');
      }
    }
  }

  Map<String, String> _environment(Object? raw) {
    if (raw == null) return const <String, String>{};
    final values = _stringMap(
      raw,
      'MCP env 字段',
      maxEntries: kMcpMaxEnvironmentCount,
    );
    _validateEnvironment(values);
    return Map<String, String>.unmodifiable(values);
  }

  void _validateEnvironment(Map<String, String> environment) {
    if (environment.length > kMcpMaxEnvironmentCount) {
      throw const FormatException('MCP 环境变量数量超过安全上限。');
    }
    for (final entry in environment.entries) {
      if (entry.key.isEmpty ||
          entry.key.length > kMcpMaxEnvironmentNameCharacters ||
          entry.value.length > kMcpMaxEnvironmentValueCharacters ||
          entry.key.contains('=') ||
          entry.key.contains('\u0000') ||
          entry.value.contains('\u0000')) {
        throw FormatException('无效的 MCP 环境变量键：${entry.key}');
      }
    }
  }

  Map<String, String> _stringMap(
    Object? raw,
    String field, {
    required int maxEntries,
  }) {
    if (raw is! Map) throw FormatException('$field 必须为对象。');
    if (raw.length > maxEntries) {
      throw FormatException('$field 的条目数量超过安全上限。');
    }
    final values = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw FormatException('$field 的值必须为文本。');
      }
      values[entry.key as String] = entry.value as String;
    }
    return values;
  }

  List<String> _stringList(Map<String, Object?> source, String key) {
    if (!source.containsKey(key)) return const <String>[];
    final raw = source[key];
    if (raw is! List ||
        raw.length > kMcpMaxArgumentCount ||
        raw.any((item) => item is! String)) {
      throw FormatException('MCP $key 必须为文本数组。');
    }
    return List<String>.unmodifiable(raw.cast<String>());
  }

  bool _optionalBool(
    Map<String, Object?> source,
    String key, {
    required bool fallback,
  }) {
    if (!source.containsKey(key)) return fallback;
    final value = source[key];
    if (value is bool) return value;
    throw FormatException('MCP $key 必须为布尔值。');
  }

  String _optionalText(Map<String, Object?> source, String key) {
    if (!source.containsKey(key)) return '';
    final value = source[key];
    if (value is String) return value;
    throw FormatException('MCP $key 必须为文本。');
  }

  Map<String, Object?> _jsonObject(Object? raw, String field) {
    if (raw is! Map) throw FormatException('$field 必须为对象。');
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw FormatException('$field 的键必须为文本。');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  Future<void> _verifySourceUnchanged() async {
    final file = File(_serversFilePath);
    final exists = await regularFileExistsBounded(file);
    if (_expectedContent == null) {
      if (exists) {
        throw StateError('MCP 配置在加载后已被修改。');
      }
      return;
    }
    if (!exists) throw StateError('MCP 配置已被外部删除。');
    final current = await readBoundedFileString(
      file,
      maxBytes: _maxServersFileBytes,
    );
    if (current != _expectedContent) {
      throw StateError('MCP 配置在加载后已被修改。');
    }
  }

  void _acceptSnapshot({
    required String? expectedContent,
    required Map<String, Object?> rootExtraFields,
  }) {
    _expectedContent = expectedContent;
    _rootExtraFields = rootExtraFields;
    _hasLoadedSnapshot = true;
    _canPersist = true;
  }

  McpLoadResult _failedLoad(McpPersistenceIssueKind kind, Object error) {
    final fallback = switch (kind) {
      McpPersistenceIssueKind.invalidContent => 'MCP 配置内容无效。',
      McpPersistenceIssueKind.loadFailed => 'MCP 配置加载失败，请稍后重试。',
      McpPersistenceIssueKind.saveFailed => 'MCP 配置保存失败，请稍后重试。',
    };
    return McpLoadResult(
      servers: const <McpServer>[],
      canPersist: false,
      issue: McpPersistenceIssue(
        kind: kind,
        filePath: _serversFilePath,
        detail: userFailureMessage(error, fallback: fallback),
      ),
    );
  }

  Future<void> openStorageDirectory() {
    return openDirectoryInFileManager(Directory(storageDirectoryPath));
  }
}

class _ParsedRoot {
  const _ParsedRoot({required this.servers, required this.rootExtraFields});

  final List<McpServer> servers;
  final Map<String, Object?> rootExtraFields;
}
