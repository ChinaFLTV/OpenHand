/// 用户指令控制器。
library;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/instructions_store.dart';
import 'model/user_instruction_entry.dart';

class InstructionsController extends ManagedChangeNotifier {
  InstructionsController._({
    required InstructionsStore store,
    required String Function() idGenerator,
    required DateTime Function() clock,
  }) : _store = store,
       _idGenerator = idGenerator,
       _clock = clock;

  factory InstructionsController.uninitialized({
    InstructionsStore? store,
    String Function()? idGenerator,
    DateTime Function()? clock,
  }) {
    return InstructionsController._(
      store: store ?? InstructionsStore(),
      idGenerator: idGenerator ?? const Uuid().v4,
      clock: clock ?? () => DateTime.now().toUtc(),
    );
  }

  final InstructionsStore _store;
  final String Function() _idGenerator;
  final DateTime Function() _clock;

  bool _isLoading = false;
  String? _errorMessage;
  List<UserInstructionEntry> _entries = const <UserInstructionEntry>[];
  List<UserInstructionEntry> _entriesView = const <UserInstructionEntry>[];
  bool _hasTrustedSnapshot = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  List<UserInstructionEntry> get entries => _entriesView;

  /// 当前所有 enabled 的指令，按 sortOrder 升序。供 prompt builder /
  /// composer 调用。
  List<UserInstructionEntry> get enabledEntries => _hasTrustedSnapshot
      ? _entriesView.where((entry) => entry.enabled).toList(growable: false)
      : const <UserInstructionEntry>[];

  final ChangePulse _saveSuccessPulse = ChangePulse();

  /// 每次 `_store.saveAll` 成功后递增，界面可据此播放提交反馈。
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    await _enqueueOperation(_loadLocked);
  }

  Future<bool> createEntry({
    required String name,
    required String body,
    String description = '',
    String version = '1.0',
    String applyTo = '',
    List<String> notes = const <String>[],
    List<String> taskTypes = const <String>[],
    List<String> keywords = const <String>[],
    bool enabled = true,
  }) async {
    final normalizedName = UserInstructionEntry.normalizeName(name);
    final normalizedBody = UserInstructionEntry.normalizeBody(body);
    if (normalizedName.isEmpty || normalizedBody.isEmpty) {
      return false;
    }
    final normalizedNotes = UserInstructionEntry.normalizeStringList(
      notes,
      maxItems: UserInstructionEntry.maxNotes,
      maxItemLength: UserInstructionEntry.maxNoteLength,
    );
    final normalizedTaskTypes = UserInstructionEntry.normalizeStringList(
      taskTypes,
      maxItems: UserInstructionEntry.maxTaskTypes,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    final normalizedKeywords = UserInstructionEntry.normalizeStringList(
      keywords,
      maxItems: UserInstructionEntry.maxKeywords,
      maxItemLength: 64,
      dedupeCaseInsensitive: true,
    );
    return _enqueueMutation(() async {
      final now = _clock().toUtc();
      final id = _idGenerator().trim();
      if (id.isEmpty || _entries.any((entry) => entry.id == id)) return false;
      // 新指令排到末尾。
      final maxOrder = _entries.isEmpty
          ? -1
          : _entries.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b);
      final next = UserInstructionEntry(
        id: id,
        name: normalizedName,
        body: normalizedBody,
        description: UserInstructionEntry.normalizeOneLine(
          description,
          UserInstructionEntry.maxDescriptionLength,
        ),
        version: UserInstructionEntry.normalizeVersion(version),
        applyTo: UserInstructionEntry.normalizeOneLine(
          applyTo,
          UserInstructionEntry.maxApplyToLength,
        ),
        notes: normalizedNotes,
        taskTypes: normalizedTaskTypes,
        keywords: normalizedKeywords,
        enabled: enabled,
        sortOrder: maxOrder + 1,
        createdAt: now,
        updatedAt: now,
      );
      return _commitSaveLocked(<UserInstructionEntry>[..._entries, next]);
    });
  }

  Future<bool> updateEntry(
    UserInstructionEntry source, {
    String? name,
    String? body,
    String? description,
    String? version,
    String? applyTo,
    List<String>? notes,
    List<String>? taskTypes,
    List<String>? keywords,
    bool? enabled,
  }) async {
    return _enqueueMutation(() async {
      final index = _entries.indexWhere((e) => e.id == source.id);
      if (index < 0) return false;
      final normalizedName = name == null
          ? _entries[index].name
          : UserInstructionEntry.normalizeName(name);
      final normalizedBody = body == null
          ? _entries[index].body
          : UserInstructionEntry.normalizeBody(body);
      if (normalizedName.isEmpty || normalizedBody.isEmpty) return false;
      final updated = _entries[index].copyWith(
        name: normalizedName,
        body: normalizedBody,
        description: description == null
            ? null
            : UserInstructionEntry.normalizeOneLine(
                description,
                UserInstructionEntry.maxDescriptionLength,
              ),
        version: version == null
            ? null
            : UserInstructionEntry.normalizeVersion(version),
        applyTo: applyTo == null
            ? null
            : UserInstructionEntry.normalizeOneLine(
                applyTo,
                UserInstructionEntry.maxApplyToLength,
              ),
        notes: notes == null
            ? null
            : UserInstructionEntry.normalizeStringList(
                notes,
                maxItems: UserInstructionEntry.maxNotes,
                maxItemLength: UserInstructionEntry.maxNoteLength,
              ),
        taskTypes: taskTypes == null
            ? null
            : UserInstructionEntry.normalizeStringList(
                taskTypes,
                maxItems: UserInstructionEntry.maxTaskTypes,
                maxItemLength: 64,
                dedupeCaseInsensitive: true,
              ),
        keywords: keywords == null
            ? null
            : UserInstructionEntry.normalizeStringList(
                keywords,
                maxItems: UserInstructionEntry.maxKeywords,
                maxItemLength: 64,
                dedupeCaseInsensitive: true,
              ),
        enabled: enabled,
        updatedAt: _clock().toUtc(),
      );
      final next = List<UserInstructionEntry>.from(_entries);
      next[index] = updated;
      return _commitSaveLocked(next);
    });
  }

  Future<bool> setEnabled(String id, bool enabled) async {
    return _enqueueMutation(() async {
      final index = _entries.indexWhere((e) => e.id == id);
      if (index < 0) return false;
      if (_entries[index].enabled == enabled) return true;
      final next = List<UserInstructionEntry>.from(_entries);
      next[index] = next[index].copyWith(
        enabled: enabled,
        updatedAt: _clock().toUtc(),
      );
      return _commitSaveLocked(next);
    });
  }

  Future<bool> deleteEntry(String id) async {
    return _enqueueMutation(() async {
      final next = _entries.where((e) => e.id != id).toList();
      if (next.length == _entries.length) return false;
      return _commitSaveLocked(next);
    });
  }

  /// 清空全部指令条目（数据清理面板使用）。单次批量提交。
  Future<bool> clearAll() async {
    return _enqueueMutation(() async {
      if (_entries.isEmpty) return true;
      return _commitSaveLocked(const <UserInstructionEntry>[]);
    });
  }

  /// 整体重排：新顺序由调用方按 UI 拖拽结果给出（id 列表）。
  /// 列表中缺失或重复的 id 会被忽略，未列出的尾随项会保持在末尾。
  Future<bool> reorder(List<String> orderedIds) async {
    return _enqueueMutation(() async {
      if (_entries.isEmpty) return true;
      final indexById = <String, int>{};
      for (int i = 0; i < orderedIds.length; i++) {
        indexById.putIfAbsent(orderedIds[i], () => i);
      }
      final reordered = List<UserInstructionEntry>.from(_entries);
      // 先按指定顺序排，未列出的按原 sortOrder 兜底。
      reordered.sort((a, b) {
        final ai = indexById[a.id] ?? (orderedIds.length + a.sortOrder);
        final bi = indexById[b.id] ?? (orderedIds.length + b.sortOrder);
        return ai.compareTo(bi);
      });
      final now = _clock().toUtc();
      for (int i = 0; i < reordered.length; i++) {
        if (reordered[i].sortOrder != i) {
          reordered[i] = reordered[i].copyWith(sortOrder: i, updatedAt: now);
        }
      }
      return _commitSaveLocked(reordered);
    });
  }

  // 内部状态管理。

  Future<void> _loadLocked() async {
    _isLoading = true;
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    notifyListeners();
    try {
      final loaded = await _store.loadAll();
      _setEntries(loaded);
      _hasTrustedSnapshot = true;
    } catch (error, stack) {
      silentLog('instructions_controller', '加载用户指令', error, stack);
      _hasTrustedSnapshot = false;
      _errorMessage = userFailureMessage(error, fallback: '用户指令加载失败，请稍后重试。');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _commitSaveLocked(List<UserInstructionEntry> next) async {
    if (!_hasTrustedSnapshot) return false;
    // 再次按 sortOrder 稳定排序。
    final sorted = List<UserInstructionEntry>.from(next)
      ..sort((a, b) {
        final cmp = a.sortOrder.compareTo(b.sortOrder);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });
    _hasTrustedSnapshot = false;
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.saveAll(sorted);
      _setEntries(sorted);
      _hasTrustedSnapshot = true;
      _saveSuccessPulse.emit();
      return true;
    } catch (error, stack) {
      silentLog('instructions_controller', '保存用户指令', error, stack);
      final saveError = userFailureMessage(error, fallback: '用户指令保存失败，请稍后重试。');
      // 保存失败后立即回读磁盘，尽快恢复可信快照。
      await _loadLocked();
      final reloadError = _hasTrustedSnapshot ? null : _errorMessage;
      final message = reloadError == null
          ? saveError
          : '$saveError；重新加载指令失败：$reloadError';
      _errorMessage = userFailureMessage(
        StateError(message),
        fallback: '用户指令保存失败，请稍后重试。',
      );
      notifyListeners();
      return false;
    }
  }

  void _setEntries(List<UserInstructionEntry> entries) {
    _entries = entries;
    _entriesView = List<UserInstructionEntry>.unmodifiable(entries);
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() operation) {
    return enqueueOperation(operation);
  }

  Future<bool> _enqueueMutation(Future<bool> Function() mutation) {
    return _enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      return mutation();
    });
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    await _loadLocked();
    return _hasTrustedSnapshot;
  }
}
