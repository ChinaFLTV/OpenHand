import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';
import 'package:openhand/features/mcp/model/mcp_tool.dart';
import 'package:openhand/features/mcp/service/mcp_keyword_index.dart';

void main() {
  late Directory temporaryDirectory;
  late File indexFile;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'openhand-mcp-keyword-index-',
    );
    indexFile = File('${temporaryDirectory.path}/keyword_index.json');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('loads a valid persisted keyword index', () async {
    await indexFile.writeAsString(jsonEncode(McpKeywordIndex.empty.toJson()));
    final service = McpKeywordIndexService(
      storageDir: temporaryDirectory,
      maxPersistedBytes: 1024,
    );

    final loaded = await service.loadFromDisk();

    expect(loaded, isNotNull);
    expect(loaded!.totalTools, 0);
    expect(loaded.totalServers, 0);
  });

  test('ignores a persisted keyword index above its byte limit', () async {
    await indexFile.writeAsString('{"padding":"${'x' * 64}"}');
    final service = McpKeywordIndexService(
      storageDir: temporaryDirectory,
      maxPersistedBytes: 32,
    );

    expect(await service.loadFromDisk(), isNull);
  });

  test('build completes only after the index is persisted', () async {
    final service = McpKeywordIndexService(
      storageDir: temporaryDirectory,
      maxPersistedBytes: 4096,
    );
    const server = McpServer(
      name: 'server',
      type: McpServerType.stdio,
      enabled: true,
    );
    const tool = McpTool(
      id: 'server:search',
      name: 'Search',
      description: 'Search files',
      inputSchema: <String, Object?>{},
    );

    final result = await service.build(
      servers: const <McpServer>[server],
      resolveTools: (_) => const <McpTool>[tool],
      onProgress: (_) {},
    );

    expect(result.index.totalTools, 1);
    expect(service.isBuilding, isFalse);
    expect(await indexFile.exists(), isTrue);
    expect((await service.loadFromDisk())?.totalTools, 1);
  });

  test('rejects a non-positive persistence limit', () {
    expect(
      () => McpKeywordIndexService(
        storageDir: temporaryDirectory,
        maxPersistedBytes: 0,
      ),
      throwsArgumentError,
    );
  });
}
