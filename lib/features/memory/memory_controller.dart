import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/memory_store.dart';
import 'model/user_memory_entry.dart';

class MemoryController extends ManagedChangeNotifier {
  MemoryController._({
    required this._store,
    required this._idGenerator,
    required this._clock,
  });

  /// 同步创建控制器，不立即加载 SQLite。调用方必须执行 [refresh]，
  /// 通常以 `unawaited(controller.refresh())` 在后台填充内存条目。
  ///
  /// 用于让 `main.dart` 避免在启动关键路径加载记忆；首页仅在用户操作触发
  /// 的运行时上下文中读取记忆，因此首帧使用空控制器并后台刷新更快。
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

  /// 每次持久化变更成功后递增，界面可据此播放提交反馈。
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<UserMemoryEntry> get entries => _entriesView;
  String get userMemoryFilePath => _store.userMemoryFilePath;
  String get storageDirectoryPath => _store.storageDirectoryPath;
  MemoryPersistenceIssue? get persistenceIssue => _persistenceIssue;
  bool get isQuotaRecoveryMode => _isQuotaRecoveryMode;

  /// 返回唯一的用户画像条目；不存在时返回 null。
  UserMemoryEntry? get userProfile {
    for (final entry in _entries) {
      if (entry.type == UserMemoryEntry.userProfileType) {
        return entry;
      }
    }
    return null;
  }

  /// 返回包含 [tag] 的全部内存条目，匹配时忽略大小写。
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

  /// 新增或更新唯一的 `user_profile` 条目，并刷新可信内存快照。
  /// 操作队列用于避免界面写入和自学习写入交错。
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
        throw StateError('更新用户画像前无法加载记忆。');
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
      } catch (error, stack) {
        silentLog('memory_controller', '清空记忆', error, stack);
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
    } catch (error, stack) {
      silentLog('memory_controller', '加载记忆', error, stack);
      _hasTrustedSnapshot = false;
      _isQuotaRecoveryMode = false;
      _errorMessage = userFailureMessage(error, fallback: '记忆加载失败，请稍后重试。');
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
    } catch (error, stack) {
      silentLog('memory_controller', '保存记忆', error, stack);
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
    } catch (error, stack) {
      silentLog('memory_controller', '重新加载记忆', error, stack);
      _hasTrustedSnapshot = false;
      _isQuotaRecoveryMode = false;
      _errorMessage = userFailureMessage(error, fallback: '记忆重新加载失败，请稍后重试。');
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
