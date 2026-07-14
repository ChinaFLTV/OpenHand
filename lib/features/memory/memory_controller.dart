import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../shared/core/managed_change_notifier.dart';
import 'data/memory_store.dart';
import 'model/user_memory_entry.dart';

class MemoryController extends ManagedChangeNotifier {
  MemoryController._({
    required MemoryStore store,
    required String Function() idGenerator,
    required DateTime Function() clock,
  }) : _store = store,
       _idGenerator = idGenerator,
       _clock = clock;

  /// Constructs a [MemoryController] synchronously without performing the
  /// initial sqlite load. Callers MUST invoke [refresh] (typically as
  /// `unawaited(controller.refresh())`) to populate the in-memory entries.
  ///
  /// Used by `main.dart` to keep memory loading off the boot critical path:
  /// the home page only reads memory entries inside user-action paths
  /// (`_buildRuntimeContext`), so providing an empty controller at first
  /// paint and refreshing in the background is safe and visibly faster.
  factory MemoryController.uninitialized({
    MemoryStore? store,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) {
    return MemoryController._(
      store: store ?? MemoryStore(),
      idGenerator: idGenerator ?? const Uuid().v4,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
  }

  static Future<MemoryController> create({
    MemoryStore? store,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) async {
    final controller = MemoryController.uninitialized(
      store: store,
      idGenerator: idGenerator,
      clock: clock,
    );
    await controller.refresh();
    return controller;
  }

  final MemoryStore _store;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  bool _isLoading = false;
  String? _errorMessage;
  List<UserMemoryEntry> _entries = const <UserMemoryEntry>[];
  List<UserMemoryEntry> _entriesView = const <UserMemoryEntry>[];
  MemoryPersistenceIssue? _persistenceIssue;
  bool _hasTrustedSnapshot = false;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  /// Increments after each successful `_store.save`. UI may listen via
  /// `HighlightPulse` to flash on commit.
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<UserMemoryEntry> get entries => _entriesView;
  String get userMemoryFilePath => _store.userMemoryFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  MemoryPersistenceIssue? get persistenceIssue => _persistenceIssue;

  /// Returns the single user profile entry in memory, or null if none.
  UserMemoryEntry? get userProfile {
    for (final entry in _entries) {
      if (entry.type == UserMemoryEntry.userProfileType) {
        return entry;
      }
    }
    return null;
  }

  /// Returns all in-memory entries carrying [tag] (case-insensitive match).
  List<UserMemoryEntry> memoriesWithTag(String tag) {
    final needle = tag.trim().toLowerCase();
    if (needle.isEmpty) {
      return const <UserMemoryEntry>[];
    }
    return _entries
        .where((entry) => entry.tags.any((t) => t.toLowerCase() == needle))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

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

  Future<bool> createMemory({
    required String content,
    required List<String> tags,
    String title = '',
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return false;
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);
    final normalizedTitle = UserMemoryEntry.normalizeTitle(title);
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final entry = UserMemoryEntry(
        id: _idGenerator(),
        type: UserMemoryEntry.userType,
        createdAt: _clock().toUtc(),
        content: normalizedContent,
        tags: normalizedTags,
        title: normalizedTitle,
      );
      final nextEntries = <UserMemoryEntry>[entry, ..._entries];
      return _commitMutationLocked(
        nextEntries,
        () => _store.insertEntry(entry),
      );
    });
  }

  Future<bool> updateMemory(
    UserMemoryEntry entry, {
    required String content,
    required List<String> tags,
    String? title,
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return false;
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);
    // null = 不变（保留旧值）；空串/非空串 = 显式覆盖（含清空）。
    final normalizedTitle = title == null
        ? null
        : UserMemoryEntry.normalizeTitle(title);
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final index = _entries.indexWhere((item) => item.id == entry.id);
      if (index == -1) {
        return false;
      }
      final nextEntries = List<UserMemoryEntry>.from(_entries);
      final nextEntry = nextEntries[index].copyWith(
        content: normalizedContent,
        tags: normalizedTags,
        type: UserMemoryEntry.userType,
        title: normalizedTitle,
      );
      nextEntries[index] = nextEntry;
      return _commitMutationLocked(
        nextEntries,
        () => _store.updateEntry(nextEntry),
      );
    });
  }

  /// Upserts the single user_profile entry and updates the trusted in-memory
  /// snapshot. The operation queue prevents UI and self-learning writes from
  /// interleaving.
  Future<UserMemoryEntry> upsertUserProfile({
    required String content,
    List<String> tags = const <String>[],
  }) {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) {
        throw StateError('Unable to load memories before updating profile.');
      }
      final entry = await _store.upsertUserProfile(
        content: content,
        tags: tags,
      );
      _setEntries(
        <UserMemoryEntry>[
          entry,
          ..._entries.where(
            (item) => item.type != UserMemoryEntry.userProfileType,
          ),
        ]..sort((left, right) => right.createdAt.compareTo(left.createdAt)),
      );
      _errorMessage = null;
      if (_persistenceIssue?.kind == MemoryPersistenceIssueKind.saveFailed) {
        _persistenceIssue = null;
      }
      _saveSuccessPulse.emit();
      notifyListeners();
      return entry;
    });
  }

  Future<bool> deleteMemory(UserMemoryEntry entry) async {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final nextEntries = _entries
          .where((item) => item.id != entry.id)
          .toList(growable: false);
      if (nextEntries.length == _entries.length) {
        return true;
      }
      return _commitMutationLocked(
        nextEntries,
        () => _store.deleteEntry(entry.id),
      );
    });
  }

  Future<void> openStorageDirectory() {
    return _store.openStorageDirectory();
  }

  Future<void> _loadLocked() async {
    _isLoading = true;
    _errorMessage = null;
    _persistenceIssue = null;
    notifyListeners();

    try {
      final loadResult = await _store.load();
      _setEntries(loadResult.entries);
      _persistenceIssue = loadResult.issue;
      _hasTrustedSnapshot = true;
    } catch (error) {
      _hasTrustedSnapshot = false;
      _errorMessage = '$error';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _commitMutationLocked(
    List<UserMemoryEntry> nextEntries,
    Future<void> Function() persist,
  ) async {
    if (!_hasTrustedSnapshot) return false;
    final previousEntries = List<UserMemoryEntry>.from(_entries);
    _setEntries(
      List<UserMemoryEntry>.from(nextEntries)
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt)),
    );
    _errorMessage = null;
    notifyListeners();
    try {
      await persist();
      _hasTrustedSnapshot = true;
      if (_persistenceIssue?.kind == MemoryPersistenceIssueKind.saveFailed) {
        _persistenceIssue = null;
        notifyListeners();
      }
      _saveSuccessPulse.emit();
      return true;
    } catch (error) {
      _setEntries(previousEntries);
      _persistenceIssue = MemoryPersistenceIssue(
        kind: MemoryPersistenceIssueKind.saveFailed,
        filePath: _store.userMemoryFilePath,
        detail: '$error',
      );
      notifyListeners();
      return false;
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    await _loadLocked();
    return _hasTrustedSnapshot;
  }

  void _setEntries(List<UserMemoryEntry> entries) {
    _entries = entries;
    _entriesView = List<UserMemoryEntry>.unmodifiable(entries);
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    return enqueueOperation(operation);
  }
}
