import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/openhand_paths.dart';
import 'data/memory_store.dart';
import 'model/user_memory_entry.dart';

class MemoryController extends ChangeNotifier {
  MemoryController._({
    required MemoryStore store,
    required String Function() idGenerator,
    required DateTime Function() clock,
  }) : _store = store,
       _idGenerator = idGenerator,
       _clock = clock;

  static Future<MemoryController> create({
    required String initialFilePath,
    MemoryStore? store,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final controller = MemoryController._(
      store: store ?? MemoryStore(userMemoryFilePath: initialFilePath),
      idGenerator: idGenerator ?? const Uuid().v4,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
    await controller.refresh();
    return controller;
  }

  MemoryStore _store;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  bool _isLoading = false;
  String? _errorMessage;
  List<UserMemoryEntry> _entries = const <UserMemoryEntry>[];
  MemoryPersistenceIssue? _persistenceIssue;
  Future<void> _operationQueue = Future<void>.value();

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<UserMemoryEntry> get entries =>
      List<UserMemoryEntry>.unmodifiable(_entries);
  String get userMemoryFilePath => _store.userMemoryFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  MemoryPersistenceIssue? get persistenceIssue => _persistenceIssue;

  void clearPersistenceIssue() {
    if (_persistenceIssue == null) {
      return;
    }
    _persistenceIssue = null;
    notifyListeners();
  }

  Future<void> refresh() async {
    await _enqueueOperation(_loadLocked);
  }

  Future<void> reloadFromFilePath(String filePath) async {
    await _enqueueOperation(() async {
      final normalizedPath = OpenHandPaths.normalizePath(
        filePath,
        defaultPath: OpenHandPaths.defaultUserMemoryFilePath(),
      );
      if (_store.userMemoryFilePath != normalizedPath) {
        _store = MemoryStore(userMemoryFilePath: normalizedPath);
      }
      await _loadLocked();
    });
  }

  Future<bool> createMemory({
    required String content,
    required List<String> tags,
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return false;
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);
    return _enqueueOperation(() async {
      final nextEntries = <UserMemoryEntry>[
        UserMemoryEntry(
          id: _idGenerator(),
          type: UserMemoryEntry.userType,
          createdAt: _clock().toUtc(),
          content: normalizedContent,
          tags: normalizedTags,
        ),
        ..._entries,
      ];
      return _commitSaveLocked(nextEntries);
    });
  }

  Future<bool> updateMemory(
    UserMemoryEntry entry, {
    required String content,
    required List<String> tags,
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return false;
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);
    return _enqueueOperation(() async {
      final index = _entries.indexWhere((item) => item.id == entry.id);
      if (index == -1) {
        return false;
      }
      final nextEntries = List<UserMemoryEntry>.from(_entries);
      nextEntries[index] = nextEntries[index].copyWith(
        content: normalizedContent,
        tags: normalizedTags,
        type: UserMemoryEntry.userType,
      );
      return _commitSaveLocked(nextEntries);
    });
  }

  Future<bool> deleteMemory(UserMemoryEntry entry) async {
    return _enqueueOperation(() async {
      final nextEntries = _entries
          .where((item) => item.id != entry.id)
          .toList(growable: false);
      if (nextEntries.length == _entries.length) {
        return true;
      }
      return _commitSaveLocked(nextEntries);
    });
  }

  Future<void> openStorageDirectory() {
    return _store.openStorageDirectory();
  }

  Future<void> _loadLocked() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final loadResult = await _store.load();
      _entries = loadResult.entries;
      _persistenceIssue = loadResult.issue;
    } catch (error) {
      _entries = const <UserMemoryEntry>[];
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _commitSaveLocked(List<UserMemoryEntry> nextEntries) async {
    final previousEntries = List<UserMemoryEntry>.from(_entries);
    _entries = List<UserMemoryEntry>.from(nextEntries)
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.save(_entries);
      if (_persistenceIssue != null) {
        _persistenceIssue = null;
        notifyListeners();
      }
      return true;
    } catch (error) {
      _entries = previousEntries;
      _persistenceIssue = MemoryPersistenceIssue(
        kind: MemoryPersistenceIssueKind.saveFailed,
        filePath: _store.userMemoryFilePath,
        detail: '$error',
      );
      notifyListeners();
      return false;
    }
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationQueue = _operationQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
