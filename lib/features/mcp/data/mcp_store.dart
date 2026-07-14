import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
import '../../../app/support/url_validation.dart';
import '../../../shared/db/atomic_file_operations.dart';
import '../../../shared/util/bounded_file_io.dart';
import '../../../shared/util/byte_size_format.dart';
import '../../../shared/util/input_value_parsing.dart';
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
      if (!await targetFile.exists()) {
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
      } catch (error) {
        return _failedLoad(McpPersistenceIssueKind.invalidContent, error);
      }
    } catch (error) {
      return _failedLoad(McpPersistenceIssueKind.loadFailed, error);
    }
  }

  Future<void> save(List<McpServer> servers) async {
    if (!_hasLoadedSnapshot || !_canPersist) {
      throw StateError('MCP configuration has no trusted snapshot.');
    }
    await _verifySourceUnchanged();
    final content = _encode(servers);
    if (utf8.encode(content).length > _maxServersFileBytes) {
      throw const FileSystemException('MCP configuration exceeds size limit.');
    }
    final targetFile = File(_serversFilePath);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }
    await writeFileAtomically(targetFile, content);
    _expectedContent = content;
  }

  _ParsedRoot _parseRoot(Object? decoded) {
    final root = _jsonObject(decoded, 'MCP root');
    final rawServers = root[_serversRootKey];
    if (rawServers is! Map) {
      throw const FormatException('mcpServers must be an object.');
    }
    final servers = <McpServer>[];
    for (final entry in rawServers.entries) {
      if (entry.key is! String) {
        throw const FormatException('MCP server name must be text.');
      }
      servers.add(_parseServer(entry.key as String, entry.value));
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
    if (name.isEmpty || name != rawName) {
      throw const FormatException('MCP server name is invalid.');
    }
    final source = _jsonObject(rawValue, 'MCP server $name');
    final url = _optionalText(source, 'url');
    final command = _optionalText(source, 'command');
    final type = _resolveType(source, url: url, command: command);
    if (type == McpServerType.stdio && command.trim().isEmpty) {
      throw FormatException('MCP stdio server $name requires command.');
    }
    if (type != McpServerType.stdio && !isValidHttpUrl(url)) {
      throw FormatException('MCP HTTP server $name has invalid URL.');
    }
    return McpServer(
      name: name,
      type: type,
      enabled: _optionalBool(source, 'enabled', fallback: true),
      probeEnabled: _optionalBool(source, 'probeEnabled', fallback: true),
      url: url,
      command: command,
      args: _stringList(source, 'args'),
      headers: _headers(source['headers']),
      environment: _environment(source['env']),
      extraFields: Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in source.entries)
          if (!_serverFields.contains(entry.key)) entry.key: entry.value,
      }),
    );
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
        throw FormatException('MCP $key must be text.');
      }
      final parsed = McpServerType.fromStorage(raw);
      if (parsed == null) throw FormatException('Unknown MCP $key: $raw');
      return parsed;
    }

    final declaredType = parseExplicit('type');
    final declaredTransport = parseExplicit('transport');
    if (declaredType != null &&
        declaredTransport != null &&
        declaredType != declaredTransport) {
      throw const FormatException('MCP type and transport conflict.');
    }
    final explicit = declaredType ?? declaredTransport;
    if (explicit != null) return explicit;
    final hasCommand = command.trim().isNotEmpty;
    final hasUrl = isValidHttpUrl(url);
    if (hasCommand == hasUrl) {
      throw const FormatException('Cannot infer MCP transport.');
    }
    return hasCommand ? McpServerType.stdio : McpServerType.streamableHttp;
  }

  String _encode(List<McpServer> servers) {
    final names = <String>{};
    final entries = <String, Object?>{};
    for (final server in servers) {
      _validateServer(server);
      if (!names.add(server.name)) {
        throw FormatException('Duplicate MCP server: ${server.name}');
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
      };
    }
    return prettyPrintJson(<String, Object?>{
      ..._rootExtraFields,
      _serversRootKey: entries,
    });
  }

  void _validateServer(McpServer server) {
    if (server.name.isEmpty || server.name.trim() != server.name) {
      throw const FormatException('MCP server name is invalid.');
    }
    if (server.type == McpServerType.stdio) {
      if (server.command.trim().isEmpty) {
        throw FormatException(
          'MCP stdio server ${server.name} requires command.',
        );
      }
    } else if (!isValidHttpUrl(server.url)) {
      throw FormatException('MCP HTTP server ${server.name} has invalid URL.');
    }
    _validateHeaders(server.headers);
    _validateEnvironment(server.environment);
  }

  Map<String, String> _headers(Object? raw) {
    if (raw == null) return const <String, String>{};
    final values = _stringMap(raw, 'MCP headers');
    _validateHeaders(values);
    return Map<String, String>.unmodifiable(values);
  }

  void _validateHeaders(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key != entry.key.trim() ||
          entry.value != entry.value.trim() ||
          !isValidMcpHttpHeader(entry.key, entry.value)) {
        throw FormatException('Invalid MCP header: ${entry.key}');
      }
    }
  }

  Map<String, String> _environment(Object? raw) {
    if (raw == null) return const <String, String>{};
    final values = _stringMap(raw, 'MCP env');
    _validateEnvironment(values);
    return Map<String, String>.unmodifiable(values);
  }

  void _validateEnvironment(Map<String, String> environment) {
    for (final entry in environment.entries) {
      if (entry.key.isEmpty ||
          entry.key.contains('=') ||
          entry.key.contains('\u0000') ||
          entry.value.contains('\u0000')) {
        throw FormatException('Invalid MCP environment key: ${entry.key}');
      }
    }
  }

  Map<String, String> _stringMap(Object? raw, String field) {
    if (raw is! Map) throw FormatException('$field must be an object.');
    final values = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw FormatException('$field values must be text.');
      }
      values[entry.key as String] = entry.value as String;
    }
    return values;
  }

  List<String> _stringList(Map<String, Object?> source, String key) {
    if (!source.containsKey(key)) return const <String>[];
    final raw = source[key];
    if (raw is! List || raw.any((item) => item is! String)) {
      throw FormatException('MCP $key must be a text array.');
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
    throw FormatException('MCP $key must be boolean.');
  }

  String _optionalText(Map<String, Object?> source, String key) {
    if (!source.containsKey(key)) return '';
    final value = source[key];
    if (value is String) return value;
    throw FormatException('MCP $key must be text.');
  }

  Map<String, Object?> _jsonObject(Object? raw, String field) {
    if (raw is! Map) throw FormatException('$field must be an object.');
    final result = <String, Object?>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw FormatException('$field keys must be text.');
      }
      result[entry.key as String] = entry.value;
    }
    return result;
  }

  Future<void> _verifySourceUnchanged() async {
    final file = File(_serversFilePath);
    final exists = await file.exists();
    if (_expectedContent == null) {
      if (exists) {
        throw StateError('MCP configuration changed after loading.');
      }
      return;
    }
    if (!exists) throw StateError('MCP configuration was removed externally.');
    final current = await readBoundedFileString(
      file,
      maxBytes: _maxServersFileBytes,
    );
    if (current != _expectedContent) {
      throw StateError('MCP configuration changed after loading.');
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
    return McpLoadResult(
      servers: const <McpServer>[],
      canPersist: false,
      issue: McpPersistenceIssue(
        kind: kind,
        filePath: _serversFilePath,
        detail: '$error',
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
