import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../app/support/openhand_paths.dart';
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
      await save(sanitized.servers);
      return McpLoadResult(
        servers: sanitized.servers,
        issue: McpPersistenceIssue(
          kind: McpPersistenceIssueKind.sanitizedInvalidContent,
          filePath: _serversFilePath,
        ),
      );
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
      final server = _parseServer(name, rawValue);
      if (server == null) {
        didSanitize = true;
        return;
      }
      final hasExplicitEnabled =
          rawValue is Map<String, dynamic> && rawValue['enabled'] is bool;
      if (!hasExplicitEnabled) {
        didSanitize = true;
      }
      servers.add(server);
    });

    return _SanitizedMcpResult(didSanitize: didSanitize, servers: servers);
  }

  McpServer? _parseServer(String name, Object? rawValue) {
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

    final isValid = switch (type) {
      McpServerType.streamableHttp || McpServerType.sse => url.isNotEmpty,
      McpServerType.stdio => command.isNotEmpty,
    };
    if (!isValid) {
      return null;
    }

    return McpServer(
      name: name,
      type: type,
      enabled: enabled,
      url: url,
      command: command,
      args: args,
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
      entries[server.name] = value;
    }
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(<String, Object?>{'mcpServers': entries});
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

  Future<void> _writeAtomically(File targetFile, String content) async {
    final tempFile = File('${targetFile.path}.tmp');
    final backupFile = File('${targetFile.path}.bak');

    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await tempFile.writeAsString(content, flush: true);

    var movedExistingFile = false;
    try {
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      if (await targetFile.exists()) {
        await targetFile.rename(backupFile.path);
        movedExistingFile = true;
      }
      await tempFile.rename(targetFile.path);
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
    } catch (_) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (movedExistingFile && await backupFile.exists()) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await backupFile.rename(targetFile.path);
      }
      rethrow;
    }
  }

  Future<void> openStorageDirectory() async {
    final directory = Directory(storageDirectoryPath);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    late final ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', <String>[directory.path]);
    } else if (Platform.isWindows) {
      result = await Process.run('explorer', <String>[directory.path]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', <String>[directory.path]);
    } else {
      throw const FileSystemException('Unsupported platform.');
    }

    if (result.exitCode != 0) {
      final message = '${result.stderr}'.trim();
      throw FileSystemException(
        message.isEmpty ? 'Unable to open directory.' : message,
      );
    }
  }
}

class _SanitizedMcpResult {
  const _SanitizedMcpResult({required this.didSanitize, required this.servers});

  final bool didSanitize;
  final List<McpServer> servers;
}
