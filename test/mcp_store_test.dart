import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/mcp/mcp_controller.dart';
import 'package:openhand/features/mcp/data/mcp_store.dart';
import 'package:openhand/features/mcp/model/mcp_server.dart';

void main() {
  test('McpStore persists and recovers MCP servers json', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_mcp_store_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final serversFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'mcp',
      'mcp_servers.json',
    );
    final store = McpStore(serversFilePath: serversFilePath);

    final initialLoad = await store.load();
    expect(initialLoad.servers, isEmpty);
    expect(File(serversFilePath).existsSync(), isTrue);

    await store.save(const <McpServer>[
      McpServer(
        name: 'amap-maps',
        type: McpServerType.streamableHttp,
        enabled: true,
        url: 'https://mcp.example/amap',
      ),
      McpServer(
        name: 'local-shell',
        type: McpServerType.stdio,
        enabled: false,
        command: 'npx',
        args: <String>['-y', '@example/mcp-shell'],
      ),
    ]);

    final reloaded = await store.load();
    expect(reloaded.servers, hasLength(2));
    expect(reloaded.servers.first.name, 'amap-maps');
    expect(reloaded.servers.last.enabled, isFalse);
    expect(File(serversFilePath).readAsStringSync(), contains('"mcpServers"'));

    await File(serversFilePath).writeAsString('{broken', flush: true);
    final recovered = await store.load();
    expect(recovered.servers, isEmpty);
    expect(recovered.issue?.kind, McpPersistenceIssueKind.recoveredInvalidFile);
    final backupFiles = Directory(p.dirname(serversFilePath))
        .listSync()
        .whereType<File>()
        .where(
          (file) => p.basename(file.path).startsWith('mcp_servers.invalid-'),
        )
        .toList();
    expect(backupFiles, isNotEmpty);
  });

  test('McpController serializes save and refresh operations', () async {
    final store = _QueuedMcpStore(initialServers: const <McpServer>[]);
    final controller = await McpController.create(
      initialFilePath: store.serversFilePath,
      store: store,
    );
    expect(store.loadCallCount, 1);

    const server = McpServer(
      name: 'amap-maps',
      type: McpServerType.streamableHttp,
      enabled: true,
      url: 'https://mcp.example/amap',
    );

    final saveFuture = controller.saveServer(server);
    final refreshFuture = controller.refresh();

    await Future<void>.delayed(Duration.zero);

    expect(store.pendingSaveCount, 1);
    expect(store.loadCallCount, 1);
    expect(controller.servers, hasLength(1));

    store.completeNextSave();

    await saveFuture;
    await refreshFuture;

    expect(store.loadCallCount, 2);
    expect(controller.servers, hasLength(1));
    expect(controller.servers.single.name, server.name);
    expect(controller.errorMessage, isNull);
  });

  test(
    'McpController applies queued saves against latest server list',
    () async {
      final store = _QueuedMcpStore(initialServers: const <McpServer>[]);
      final controller = await McpController.create(
        initialFilePath: store.serversFilePath,
        store: store,
      );

      const firstServer = McpServer(
        name: 'amap-maps',
        type: McpServerType.streamableHttp,
        enabled: true,
        url: 'https://mcp.example/amap',
      );
      const secondServer = McpServer(
        name: 'local-shell',
        type: McpServerType.stdio,
        enabled: false,
        command: 'npx',
        args: <String>['-y', '@example/mcp-shell'],
      );

      final firstSave = controller.saveServer(firstServer);
      final secondSave = controller.saveServer(secondServer);

      await Future<void>.delayed(Duration.zero);
      expect(store.pendingSaveCount, 1);
      expect(controller.servers, hasLength(1));

      store.completeNextSave();
      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(controller.servers, hasLength(2));

      store.completeNextSave();

      expect(await firstSave, isTrue);
      expect(await secondSave, isTrue);
      expect(controller.servers, hasLength(2));
      expect(controller.servers.first.name, 'amap-maps');
      expect(controller.servers.last.name, 'local-shell');
    },
  );
}

class _QueuedMcpStore extends McpStore {
  _QueuedMcpStore({required List<McpServer> initialServers})
    : _persistedServers = List<McpServer>.from(initialServers),
      super(serversFilePath: '/tmp/openhand-test-mcp.json');

  List<McpServer> _persistedServers;
  int loadCallCount = 0;
  final List<_PendingMcpSave> _pendingSaves = <_PendingMcpSave>[];

  int get pendingSaveCount => _pendingSaves.length;

  @override
  Future<McpLoadResult> load() async {
    loadCallCount += 1;
    return McpLoadResult(servers: List<McpServer>.from(_persistedServers));
  }

  @override
  Future<void> save(List<McpServer> servers) {
    final completer = Completer<void>();
    _pendingSaves.add(
      _PendingMcpSave(
        completer: completer,
        servers: List<McpServer>.from(servers),
      ),
    );
    return completer.future;
  }

  void completeNextSave() {
    final pendingSave = _pendingSaves.removeAt(0);
    _persistedServers = pendingSave.servers;
    pendingSave.completer.complete();
  }
}

class _PendingMcpSave {
  const _PendingMcpSave({required this.completer, required this.servers});

  final Completer<void> completer;
  final List<McpServer> servers;
}
