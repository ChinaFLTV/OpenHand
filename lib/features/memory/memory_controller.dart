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
  bool _isQuotaRecoveryMode = false;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  /// Increments after each successful persistent mutation. UI may listen via
  /// `HighlightPulse` to flash on commit.
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<UserMemoryEntry> get entries => _entriesView;
  String get userMemoryFilePath => _store.userMemoryFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  MemoryPersistenceIssue? get persistenceIssue => _persistenceIssue;
  bool get isQuotaRecoveryMode => _isQuotaRecoveryMode;

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

  Future<bool> ensureLoaded() =>
      _enqueueOperation(_ensureTrustedSnapshotLocked);

  Future<List<UserMemoryEntry>?> trustedEntriesSnapshot() {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return null;
      return _entriesView;
    });
  }

  Future<bool> createMemory({
    required String content,
    required List<String> tags,
    String title = '',
  }) async =>
      await createMemoryEntry(content: content, tags: tags, title: title) !=
      null;

  Future<UserMemoryEntry?> createMemoryEntry({
    required String content,
    required List<String> tags,
    String title = '',
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return null;
    }
    final normalizedTags = UserMemoryEntry.normalizeTags(tags);
    final normalizedTitle = UserMemoryEntry.normalizeTitle(title);
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return null;
      if (_isQuotaRecoveryMode) return null;
      final entry = UserMemoryEntry(
        id: _idGenerator(),
        type: UserMemoryEntry.userType,
        createdAt: _clock().toUtc(),
        content: normalizedContent,
        tags: normalizedTags,
        title: normalizedTitle,
      );
      final nextEntries = <UserMemoryEntry>[entry, ..._entries];
      final committed = await _commitMutationLocked(
        nextEntries,
        () => _store.insertEntry(entry),
      );
      return committed ? entry : null;
    });
  }

  Future<bool> updateMemory(
    UserMemoryEntry entry, {
    required String content,
    List<String>? tags,
    String? title,
  }) async {
    final normalizedContent = UserMemoryEntry.normalizeContent(content);
    if (normalizedContent.isEmpty) {
      return false;
    }
    final normalizedTags = tags == null
        ? null
        : UserMemoryEntry.normalizeTags(tags);
    // null = 不变（保留旧值）；空串/非空串 = 显式覆盖（含清空）。
    final normalizedTitle = title == null
        ? null
        : UserMemoryEntry.normalizeTitle(title);
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final index = _entries.indexWhere((item) => item.id == entry.id);
      if (index == -1 || !identical(_entries[index], entry)) {
        return false;
      }
      final nextEntries = List<UserMemoryEntry>.from(_entries);
      final nextEntry = nextEntries[index].copyWith(
        content: normalizedContent,
        tags: normalizedTags,
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
    List<String>? tags,
  }) async {
    final entry = await _upsertUserProfile(
      content: content,
      tags: tags,
      requireUnchangedProfile: false,
    );
    return entry!;
  }

  Future<UserMemoryEntry?> upsertUserProfileIfUnchanged({
    required String content,
    required UserMemoryEntry? expectedProfile,
    List<String>? tags,
  }) {
    return _upsertUserProfile(
      content: content,
      tags: tags,
      requireUnchangedProfile: true,
      expectedProfile: expectedProfile,
    );
  }

  Future<UserMemoryEntry?> _upsertUserProfile({
    required String content,
    required bool requireUnchangedProfile,
    UserMemoryEntry? expectedProfile,
    List<String>? tags,
  }) {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) {
        throw StateError('Unable to load memories before updating profile.');
      }
      if (requireUnchangedProfile && !identical(userProfile, expectedProfile)) {
        return null;
      }
      try {
        final entry = await _store.upsertUserProfile(
          content: content,
          tags: tags,
        );
        if (_isQuotaRecoveryMode) {
          await _reloadAfterRecoveryMutation();
        } else {
          _publishSuccessfulMutation(<UserMemoryEntry>[
            entry,
            ..._entries.where(
              (item) => item.type != UserMemoryEntry.userProfileType,
            ),
          ]);
        }
        return entry;
      } catch (_) {
        _publishSaveFailure();
        rethrow;
      }
    });
  }

  Future<bool> deleteMemory(UserMemoryEntry entry) async {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final index = _entries.indexWhere((item) => item.id == entry.id);
      if (index == -1) return true;
      if (!identical(_entries[index], entry)) return false;
      final nextEntries = List<UserMemoryEntry>.from(_entries)..removeAt(index);
      return _commitMutationLocked(
        nextEntries,
        () => _store.deleteEntry(entry.id),
      );
    });
  }

  Future<bool> clearAll() {
    return _enqueueOperation(() async {
      try {
        await _store.clearAll();
        _publishSuccessfulMutation(const <UserMemoryEntry>[]);
        return true;
      } catch (_) {
        _publishSaveFailure();
        return false;
      }
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
      _hasTrustedSnapshot = true;
      _isQuotaRecoveryMode = loadResult.isOverQuota;
    } catch (error) {
      _hasTrustedSnapshot = false;
      _isQuotaRecoveryMode = false;
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
    try {
      await persist();
    } catch (_) {
      _publishSaveFailure();
      return false;
    }
    if (_isQuotaRecoveryMode) {
      await _reloadAfterRecoveryMutation();
    } else {
      _publishSuccessfulMutation(nextEntries);
    }
    return true;
  }

  Future<void> _reloadAfterRecoveryMutation() async {
    try {
      final loadResult = await _store.load();
      _publishSuccessfulMutation(
        loadResult.entries,
        isQuotaRecoveryMode: loadResult.isOverQuota,
      );
    } catch (error) {
      _hasTrustedSnapshot = false;
      _isQuotaRecoveryMode = false;
      _errorMessage = '$error';
      _persistenceIssue = null;
      _saveSuccessPulse.emit();
      notifyListeners();
    }
  }

  void _publishSuccessfulMutation(
    List<UserMemoryEntry> entries, {
    bool isQuotaRecoveryMode = false,
  }) {
    _setEntries(
      List<UserMemoryEntry>.from(entries)
        ..sort((left, right) => right.createdAt.compareTo(left.createdAt)),
    );
    _hasTrustedSnapshot = true;
    _isQuotaRecoveryMode = isQuotaRecoveryMode;
    _errorMessage = null;
    if (_persistenceIssue != null) {
      _persistenceIssue = null;
    }
    _saveSuccessPulse.emit();
    notifyListeners();
  }

  void _publishSaveFailure() {
    _hasTrustedSnapshot = false;
    _persistenceIssue = MemoryPersistenceIssue(
      filePath: _store.userMemoryFilePath,
    );
    notifyListeners();
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
