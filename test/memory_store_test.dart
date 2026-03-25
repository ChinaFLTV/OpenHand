import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:openhand/features/memory/data/memory_store.dart';
import 'package:openhand/features/memory/memory_controller.dart';
import 'package:openhand/features/memory/model/user_memory_entry.dart';

void main() {
  test('MemoryStore persists and recovers user memory json', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'openhand_memory_store_test_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final userMemoryFilePath = p.join(
      tempDirectory.path,
      '.openhand',
      'memory',
      'user-memory.json',
    );
    final store = MemoryStore(userMemoryFilePath: userMemoryFilePath);

    final initialLoad = await store.load();
    expect(initialLoad.entries, isEmpty);
    expect(File(userMemoryFilePath).existsSync(), isTrue);

    await store.save(<UserMemoryEntry>[
      UserMemoryEntry(
        id: 'memory-1',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 3, 22, 9, 0, 0),
        content: 'Remember the preferred terminal layout.',
        tags: const <String>['ui', 'terminal'],
      ),
      UserMemoryEntry(
        id: 'memory-2',
        type: UserMemoryEntry.userType,
        createdAt: DateTime.utc(2026, 3, 22, 10, 0, 0),
        content: 'Always keep MCP and skills settings separate.',
        tags: const <String>['settings'],
      ),
    ]);

    final reloaded = await store.load();
    expect(reloaded.entries, hasLength(2));
    expect(reloaded.entries.first.id, 'memory-2');
    expect(reloaded.entries.last.tags, contains('terminal'));
    expect(
      File(userMemoryFilePath).readAsStringSync(),
      contains('"created_at"'),
    );

    await File(userMemoryFilePath).writeAsString('{broken', flush: true);
    final recovered = await store.load();
    expect(recovered.entries, isEmpty);
    expect(
      recovered.issue?.kind,
      MemoryPersistenceIssueKind.recoveredInvalidFile,
    );
    final backupFiles = Directory(p.dirname(userMemoryFilePath))
        .listSync()
        .whereType<File>()
        .where(
          (file) => p.basename(file.path).startsWith('user-memory.invalid-'),
        )
        .toList();
    expect(backupFiles, isNotEmpty);
  });

  test(
    'MemoryStore preserves sanitized entries when rewriting them fails during load',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'openhand_memory_store_sanitize_save_failure_test_',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final userMemoryFilePath = p.join(
        tempDirectory.path,
        '.openhand',
        'memory',
        'user-memory.json',
      );
      final targetFile = File(userMemoryFilePath);
      await targetFile.parent.create(recursive: true);
      await targetFile.writeAsString('''
[
  {
    "id": "memory-1",
    "type": "user",
    "created_at": "2026-03-22T09:00:00.000Z",
    "content": "Remember the preferred terminal layout."
  }
]
''', flush: true);

      final store = _FailingSanitizedMemoryStore(
        userMemoryFilePath: userMemoryFilePath,
      );
      final result = await store.load();

      expect(result.entries, hasLength(1));
      expect(result.entries.single.id, 'memory-1');
      expect(result.entries.single.tags, isEmpty);
      expect(result.issue?.kind, MemoryPersistenceIssueKind.saveFailed);
      expect(result.issue?.filePath, userMemoryFilePath);
      expect(result.issue?.detail, contains('Injected memory save failure'));
      expect(await targetFile.exists(), isTrue);
      expect(await targetFile.readAsString(), contains('"content"'));
      expect(
        Directory(targetFile.parent.path).listSync().whereType<File>().where(
          (file) => p.basename(file.path).startsWith('user-memory.invalid-'),
        ),
        isEmpty,
      );
    },
  );

  test('MemoryController serializes create and refresh operations', () async {
    final store = _QueuedMemoryStore(initialEntries: const <UserMemoryEntry>[]);
    final controller = await MemoryController.create(
      initialFilePath: store.userMemoryFilePath,
      store: store,
      idGenerator: () => 'memory-1',
      clock: () => DateTime.utc(2026, 3, 22, 9, 0, 0),
    );
    expect(store.loadCallCount, 1);

    final createFuture = controller.createMemory(
      content: 'Remember the preferred terminal layout.',
      tags: const <String>['ui'],
    );
    final refreshFuture = controller.refresh();

    await Future<void>.delayed(Duration.zero);

    expect(store.pendingSaveCount, 1);
    expect(store.loadCallCount, 1);
    expect(controller.entries, hasLength(1));

    store.completeNextSave();

    expect(await createFuture, isTrue);
    await refreshFuture;

    expect(store.loadCallCount, 2);
    expect(controller.entries, hasLength(1));
    expect(controller.entries.single.id, 'memory-1');
    expect(controller.errorMessage, isNull);
  });

  test(
    'MemoryController applies queued creates against latest memory list',
    () async {
      final store = _QueuedMemoryStore(
        initialEntries: const <UserMemoryEntry>[],
      );
      final generatedIds = <String>['memory-1', 'memory-2'];
      final generatedTimes = <DateTime>[
        DateTime.utc(2026, 3, 22, 9, 0, 0),
        DateTime.utc(2026, 3, 22, 10, 0, 0),
      ];
      final controller = await MemoryController.create(
        initialFilePath: store.userMemoryFilePath,
        store: store,
        idGenerator: () => generatedIds.removeAt(0),
        clock: () => generatedTimes.removeAt(0),
      );

      final firstCreate = controller.createMemory(
        content: 'Remember the preferred terminal layout.',
        tags: const <String>['ui'],
      );
      final secondCreate = controller.createMemory(
        content: 'Remember the compact composer spacing.',
        tags: const <String>['layout'],
      );

      await Future<void>.delayed(Duration.zero);
      expect(store.pendingSaveCount, 1);
      expect(controller.entries, hasLength(1));

      store.completeNextSave();
      await Future<void>.delayed(Duration.zero);

      expect(store.pendingSaveCount, 1);
      expect(controller.entries, hasLength(2));

      store.completeNextSave();

      expect(await firstCreate, isTrue);
      expect(await secondCreate, isTrue);
      expect(controller.entries, hasLength(2));
      expect(controller.entries.first.id, 'memory-2');
      expect(controller.entries.last.id, 'memory-1');
    },
  );

  test(
    'MemoryController ignores late refresh completion after dispose',
    () async {
      final store = _QueuedMemoryStore(
        initialEntries: const <UserMemoryEntry>[],
      );
      final controller = await MemoryController.create(
        initialFilePath: store.userMemoryFilePath,
        store: store,
        idGenerator: () => 'memory-1',
        clock: () => DateTime.utc(2026, 3, 22, 9, 0, 0),
      );

      store.blockNextLoad();
      final refreshFuture = controller.refresh();

      await Future<void>.delayed(Duration.zero);
      expect(store.pendingLoadCount, 1);

      controller.dispose();
      store.completeNextLoad();

      await refreshFuture;
    },
  );

  test(
    'MemoryController restores the previous file path when reloading a new path fails',
    () async {
      const initialPath = '/tmp/openhand-memory-initial.json';
      const invalidPath = '/broken/user-memory.json';
      final initialEntries = <UserMemoryEntry>[
        UserMemoryEntry(
          id: 'memory-1',
          type: UserMemoryEntry.userType,
          createdAt: DateTime.utc(2026, 3, 22, 9, 0, 0),
          content: 'Remember the preferred terminal layout.',
          tags: const <String>['ui'],
        ),
      ];
      final controller = await MemoryController.create(
        initialFilePath: initialPath,
        store: _PathAwareMemoryStore(
          userMemoryFilePath: initialPath,
          entries: initialEntries,
          failingPaths: const <String>{invalidPath},
        ),
        storeFactory: (filePath) => _PathAwareMemoryStore(
          userMemoryFilePath: filePath,
          entries: initialEntries,
          failingPaths: const <String>{invalidPath},
        ),
      );

      await controller.reloadFromFilePath(invalidPath);

      expect(controller.userMemoryFilePath, initialPath);
      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.id, 'memory-1');
      expect(controller.errorMessage, isNull);
      expect(controller.persistenceIssue, isNull);
    },
  );
}

class _QueuedMemoryStore extends MemoryStore {
  _QueuedMemoryStore({required List<UserMemoryEntry> initialEntries})
    : _persistedEntries = List<UserMemoryEntry>.from(initialEntries),
      super(userMemoryFilePath: '/tmp/openhand-test-memory.json');

  List<UserMemoryEntry> _persistedEntries;
  int loadCallCount = 0;
  final List<_PendingMemorySave> _pendingSaves = <_PendingMemorySave>[];
  final List<Completer<void>> _pendingLoads = <Completer<void>>[];
  bool _blockLoads = false;

  int get pendingSaveCount => _pendingSaves.length;
  int get pendingLoadCount => _pendingLoads.length;

  @override
  Future<MemoryLoadResult> load() async {
    loadCallCount += 1;
    if (_blockLoads) {
      final completer = Completer<void>();
      _pendingLoads.add(completer);
      _blockLoads = false;
      await completer.future;
    }
    return MemoryLoadResult(
      entries: List<UserMemoryEntry>.from(_persistedEntries),
    );
  }

  @override
  Future<void> save(List<UserMemoryEntry> entries) {
    final completer = Completer<void>();
    _pendingSaves.add(
      _PendingMemorySave(
        completer: completer,
        entries: List<UserMemoryEntry>.from(entries),
      ),
    );
    return completer.future;
  }

  void completeNextSave() {
    final pendingSave = _pendingSaves.removeAt(0);
    _persistedEntries = pendingSave.entries;
    pendingSave.completer.complete();
  }

  void blockNextLoad() {
    _blockLoads = true;
  }

  void completeNextLoad() {
    final completer = _pendingLoads.removeAt(0);
    completer.complete();
  }
}

class _PathAwareMemoryStore extends MemoryStore {
  _PathAwareMemoryStore({
    required super.userMemoryFilePath,
    required List<UserMemoryEntry> entries,
    required Set<String> failingPaths,
  }) : _entries = List<UserMemoryEntry>.from(entries),
       _failingPaths = failingPaths;

  final List<UserMemoryEntry> _entries;
  final Set<String> _failingPaths;

  @override
  Future<MemoryLoadResult> load() async {
    if (_failingPaths.contains(userMemoryFilePath)) {
      throw const FileSystemException('Injected memory reload failure');
    }
    return MemoryLoadResult(entries: List<UserMemoryEntry>.from(_entries));
  }

  @override
  Future<void> save(List<UserMemoryEntry> entries) async {}
}

class _FailingSanitizedMemoryStore extends MemoryStore {
  _FailingSanitizedMemoryStore({required super.userMemoryFilePath});

  @override
  Future<void> save(List<UserMemoryEntry> entries) async {
    throw const FileSystemException('Injected memory save failure');
  }
}

class _PendingMemorySave {
  const _PendingMemorySave({required this.completer, required this.entries});

  final Completer<void> completer;
  final List<UserMemoryEntry> entries;
}
