import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/url_validation.dart';
import '../../../app/support/openhand_paths.dart';
import '../../../shared/data/atomic_file_operations.dart';
import '../model/mcp_server.dart';

enum McpPersistenceIssueKind {
  recoveredInvalidFile,
  sanitizedInvalidContent,
  saveFailed,
}

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
  const McpLoadResult({required this.servers, this.issue});

  final List<McpServer> servers;
  final McpPersistenceIssue? issue;
}

class McpStore {
  McpStore({String? serversFilePath})
    : _serversFilePath =
          serversFilePath ?? OpenHandPaths.defaultMcpServersFilePath();

  final String _serversFilePath;

  String get serversFilePath => _serversFilePath;
  String get storageDirectoryPath => p.dirname(_serversFilePath);

  Future<McpLoadResult> load() async {
    final targetFile = File(_serversFilePath);
    if (!await targetFile.exists()) {
      final servers = const <McpServer>[];
      try {
        await save(servers);
        return const McpLoadResult(servers: <McpServer>[]);
      } catch (error) {
        return McpLoadResult(
          servers: servers,
          issue: McpPersistenceIssue(
            kind: McpPersistenceIssueKind.saveFailed,
            filePath: _serversFilePath,
            detail: '$error',
          ),
        );
      }
    }

    late final String rawContent;
    try {
      rawContent = await targetFile.readAsString();
    } catch (error) {
      return McpLoadResult(
        servers: const <McpServer>[],
        issue: McpPersistenceIssue(
          kind: McpPersistenceIssueKind.saveFailed,
          filePath: _serversFilePath,
          detail: '$error',
        ),
      );
    }

    try {
      final decoded = jsonDecode(rawContent);
      final sanitized = _sanitize(decoded);
      if (!sanitized.didSanitize) {
        return McpLoadResult(servers: sanitized.servers);
      }
      try {
        await save(sanitized.servers);
        return McpLoadResult(
          servers: sanitized.servers,
          issue: McpPersistenceIssue(
            kind: McpPersistenceIssueKind.sanitizedInvalidContent,
            filePath: _serversFilePath,
          ),
        );
      } catch (error) {
        return McpLoadResult(
          servers: sanitized.servers,
          issue: McpPersistenceIssue(
            kind: McpPersistenceIssueKind.saveFailed,
            filePath: _serversFilePath,
            detail: '$error',
          ),
        );
      }
    } catch (error) {
      try {
        final backupPath = await _backupInvalidFile(targetFile);
        await save(const <McpServer>[]);
        return McpLoadResult(
          servers: const <McpServer>[],
          issue: McpPersistenceIssue(
            kind: McpPersistenceIssueKind.recoveredInvalidFile,
            filePath: backupPath,
            detail: '$error',
          ),
        );
      } catch (saveError) {
        return McpLoadResult(
          servers: const <McpServer>[],
          issue: McpPersistenceIssue(
            kind: McpPersistenceIssueKind.saveFailed,
            filePath: _serversFilePath,
            detail: '$error\n$saveError',
          ),
        );
      }
    }
  }

  Future<void> save(List<McpServer> servers) async {
    final targetFile = File(_serversFilePath);
    final targetDirectory = targetFile.parent;
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }
    final content = _encode(servers);
    await _writeAtomically(targetFile, content);
  }

  _SanitizedMcpResult _sanitize(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Root JSON is invalid.');
    }

    var didSanitize = false;
    final rawServers = decoded['mcpServers'];
    if (rawServers is! Map<String, dynamic>) {
      return const _SanitizedMcpResult(
        didSanitize: true,
        servers: <McpServer>[],
      );
    }

    final servers = <McpServer>[];
    rawServers.forEach((rawName, rawValue) {
      final name = rawName.toString().trim();
      final parsedServer = _parseServer(name, rawValue);
      if (parsedServer == null) {
        didSanitize = true;
        return;
      }
      final hasExplicitEnabled =
          rawValue is Map<String, dynamic> && rawValue['enabled'] is bool;
      if (!hasExplicitEnabled) {
        didSanitize = true;
      }
      if (parsedServer.didSanitize) {
        didSanitize = true;
      }
      servers.add(parsedServer.server);
    });

    return _SanitizedMcpResult(didSanitize: didSanitize, servers: servers);
  }

  _ParsedMcpServer? _parseServer(String name, Object? rawValue) {
    if (name.isEmpty || rawValue is! Map<String, dynamic>) {
      return null;
    }
    final type =
        McpServerType.fromStorage('${rawValue['type'] ?? ''}'.trim()) ??
        McpServerType.fromStorage('${rawValue['transport'] ?? ''}'.trim());
    if (type == null) {
      return null;
    }
    final enabled = rawValue['enabled'] is bool
        ? rawValue['enabled'] as bool
        : true;
    final url = '${rawValue['url'] ?? ''}'.trim();
    final command = '${rawValue['command'] ?? ''}'.trim();
    final rawArgs = rawValue['args'];
    final args = rawArgs is List
        ? rawArgs
              .map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final parsedHeaders = _parseHeaders(rawValue['headers']);

    final isValid = switch (type) {
      McpServerType.streamableHttp || McpServerType.sse => isValidHttpUrl(url),
      McpServerType.stdio => command.isNotEmpty,
    };
    if (!isValid) {
      return null;
    }

    return _ParsedMcpServer(
      server: McpServer(
        name: name,
        type: type,
        enabled: enabled,
        url: url,
        command: command,
        args: args,
        headers: parsedHeaders.headers,
      ),
      didSanitize: parsedHeaders.didSanitize,
    );
  }

  String _encode(List<McpServer> servers) {
    final entries = <String, Object?>{};
    for (final server in servers) {
      final value = <String, Object?>{
        'enabled': server.enabled,
        'type': server.type.storageValue,
        'transport': server.type.transportValue,
      };
      if (server.type == McpServerType.streamableHttp ||
          server.type == McpServerType.sse) {
        value['url'] = server.url.trim();
      } else {
        value['command'] = server.command.trim();
        if (server.args.isNotEmpty) {
          value['args'] = server.args
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
        }
      }
      if (server.headers.isNotEmpty) {
        value['headers'] = Map<String, String>.from(server.headers);
      }
      entries[server.name] = value;
    }
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'mcpServers': entries});
  }

  _ParsedHeaders _parseHeaders(Object? rawHeaders) {
    if (rawHeaders == null) {
      return const _ParsedHeaders(headers: <String, String>{});
    }
    if (rawHeaders is! Map) {
      return const _ParsedHeaders(
        headers: <String, String>{},
        didSanitize: true,
      );
    }
    var didSanitize = false;
    final headers = <String, String>{};
    rawHeaders.forEach((rawName, rawValue) {
      final name = '$rawName'.trim();
      final value = '$rawValue'.trim();
      if (name.isEmpty || value.isEmpty || value == 'null') {
        didSanitize = true;
        return;
      }
      headers[name] = value;
    });
    return _ParsedHeaders(
      headers: Map<String, String>.unmodifiable(headers),
      didSanitize: didSanitize,
    );
  }

  Future<String> _backupInvalidFile(File sourceFile) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final backupPath = p.join(
      sourceFile.parent.path,
      'mcp_servers.invalid-$stamp.json',
    );
    final backupFile = File(backupPath);
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await sourceFile.rename(backupPath);
    return backupPath;
  }

  Future<void> _writeAtomically(File targetFile, String content) {
    return writeFileAtomically(targetFile, content);
  }

  Future<void> openStorageDirectory() {
    return openDirectoryInFileManager(Directory(storageDirectoryPath));
  }
}

class _SanitizedMcpResult {
  const _SanitizedMcpResult({required this.didSanitize, required this.servers});

  final bool didSanitize;
  final List<McpServer> servers;
}

class _ParsedMcpServer {
  const _ParsedMcpServer({required this.server, this.didSanitize = false});

  final McpServer server;
  final bool didSanitize;
}

class _ParsedHeaders {
  const _ParsedHeaders({required this.headers, this.didSanitize = false});

  final Map<String, String> headers;
  final bool didSanitize;
}
