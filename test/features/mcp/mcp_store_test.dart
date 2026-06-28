import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late String configPath;
  late McpStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openhand_mcp_store_test_');
    configPath = p.join(tempDir.path, 'mcp_servers.json');
    store = McpStore(serversFilePath: configPath);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('load creates an empty config when the file is missing', () async {
    final result = await store.load();

    expect(result.issue, isNull);
    expect(result.servers, isEmpty);
    expect(await File(configPath).exists(), isTrue);
    expect(_readRoot(configPath)['mcpServers'], <String, Object?>{});
  });

  test(
    'load sanitizes loose server config and rewrites normalized JSON',
    () async {
      await File(configPath).writeAsString('''
      {
        "mcpServers": {
          " remote ": {
            "transport": "http",
            "url": " https://example.com/mcp ",
            "enabled": "false",
            "probeEnabled": "0",
            "headers": {
              " Authorization ": " Bearer token ",
              "Blank": "",
              "Null": null
            }
          },
          "local": {
            "type": "stdio",
            "command": " npx ",
            "args": [" -y ", "", null, "pkg"],
            "enabled": true,
            "probeEnabled": true
          },
          "bad": {
            "type": "stdio",
            "command": " "
          }
        }
      }
    ''');

      final result = await store.load();

      expect(
        result.issue?.kind,
        McpPersistenceIssueKind.sanitizedInvalidContent,
      );
      expect(result.servers.map((server) => server.name), <String>[
        'remote',
        'local',
      ]);

      final remote = result.servers.first;
      expect(remote.type, McpServerType.streamableHttp);
      expect(remote.enabled, isFalse);
      expect(remote.probeEnabled, isFalse);
      expect(remote.url, 'https://example.com/mcp');
      expect(remote.headers, <String, String>{'Authorization': 'Bearer token'});

      final local = result.servers.last;
      expect(local.type, McpServerType.stdio);
      expect(local.command, 'npx');
      expect(local.args, <String>['-y', 'pkg']);

      final normalized = _readRoot(configPath);
      final servers = normalized['mcpServers']! as Map<String, Object?>;
      expect(servers.keys, <String>['remote', 'local']);
      expect((servers['remote']! as Map<String, Object?>)['enabled'], isFalse);
      expect((servers['local']! as Map<String, Object?>)['args'], <Object?>[
        '-y',
        'pkg',
      ]);
    },
  );

  test(
    'load backs up invalid root JSON and recovers with an empty config',
    () async {
      await File(configPath).writeAsString('[]');

      final result = await store.load();

      expect(result.issue?.kind, McpPersistenceIssueKind.recoveredInvalidFile);
      expect(result.servers, isEmpty);
      expect(await File(configPath).exists(), isTrue);
      expect(_readRoot(configPath)['mcpServers'], <String, Object?>{});

      final backups = await tempDir
          .list()
          .where(
            (entity) =>
                p.basename(entity.path).startsWith('mcp_servers.invalid-'),
          )
          .toList();
      expect(backups, hasLength(1));
    },
  );
}

Map<String, Object?> _readRoot(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  expect(decoded, isA<Map>());
  return (decoded as Map).map((key, value) => MapEntry('$key', value));
}
