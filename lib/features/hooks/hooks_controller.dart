import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/hook_config.dart';
import '../../app/support/silent_log.dart';
import '../../shared/core/managed_change_notifier.dart';
import '../../shared/util/user_failure_message.dart';
import 'data/hooks_store.dart';

/// Hook 配置控制器。
///
/// 与 SettingsController、McpController 共用 ChangeNotifier 和变更队列模式。
class HooksController extends ManagedChangeNotifier {
  HooksController._({required this._store, required List<HookEntry> entries})
    : _entries = entries,
      _entriesView = List<HookEntry>.unmodifiable(entries);

  static const Uuid _uuid = Uuid();

  static Future<HooksController> create({HooksStore? store}) async {
    final effectiveStore = store ?? HooksStore();
    final controller = HooksController._(
      store: effectiveStore,
      entries: const <HookEntry>[],
    );
    await controller.refresh();
    return controller;
  }

  final HooksStore _store;
  List<HookEntry> _entries;
  List<HookEntry> _entriesView;
  bool _isLoading = true;
  String? _errorMessage;
  bool _hasTrustedSnapshot = false;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  List<HookEntry> get entries => _entriesView;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  /// 返回指定事件的全部可用 Hook。
  List<HookEntry> enabledHooksForEvent(HookEvent event) {
    if (!_hasTrustedSnapshot) return const <HookEntry>[];
    return _entries
        .where(
          (entry) => entry.event == event && entry.enabled && entry.hasScript,
        )
        .toList(growable: false);
  }

  @override
  void dispose() {
    _saveSuccessPulse.dispose();
    super.dispose();
  }

  Future<bool> addHook(HookEntry entry) async {
    return _commitMutation(() async {
      final requestedId = entry.id.trim();
      final id = requestedId.isEmpty ? _uuid.v4() : requestedId;
      if (_entries.any((item) => item.id == id)) return false;
      final next = <HookEntry>[..._entries, entry.copyWith(id: id)];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<bool> updateHook(HookEntry updated) async {
    return _commitMutation(() async {
      final id = updated.id.trim();
      if (id.isEmpty) return false;
      final index = _entries.indexWhere((item) => item.id == id);
      if (index < 0) return false;
      final next = <HookEntry>[
        ..._entries.sublist(0, index),
        updated.copyWith(id: id),
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<bool> deleteHook(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;
    return _commitMutation(() async {
      final before = _entries.length;
      final next = _entries.where((item) => item.id != normalizedId).toList();
      if (next.length == before) return false;
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<bool> toggleHookEnabled(String id, {required bool enabled}) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return false;
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == normalizedId);
      if (index < 0) return false;
      final next = <HookEntry>[
        ..._entries.sublist(0, index),
        _entries[index].copyWith(enabled: enabled),
        ..._entries.sublist(index + 1),
      ];
      await _store.saveAll(next);
      _setEntries(next);
      return true;
    });
  }

  Future<void> refresh() async {
    await enqueueOperation(_loadLocked);
  }

  /// 删除所有 hook 条目（数据清理面板使用）。批处理走单次 saveAll([])。
  Future<bool> clearAll() async {
    return _commitMutation(() async {
      if (_entries.isEmpty) return true;
      await _store.saveAll(const <HookEntry>[]);
      _setEntries(const <HookEntry>[]);
      return true;
    });
  }

  void _setEntries(List<HookEntry> entries) {
    _entries = entries;
    _entriesView = List<HookEntry>.unmodifiable(entries);
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    return enqueueOperation(() async {
      if (!await _ensureTrustedSnapshotLocked()) return false;
      final previousEntries = List<HookEntry>.from(_entries);
      _errorMessage = null;
      notifyListeners();
      try {
        final result = await mutation();
        _hasTrustedSnapshot = true;
        if (result) {
          _saveSuccessPulse.emit();
        }
        notifyListeners();
        return result;
      } catch (error, stack) {
        silentLog('hooks_controller', '保存 Hook 配置', error, stack);
        _setEntries(previousEntries);
        _hasTrustedSnapshot = true;
        _errorMessage = userFailureMessage(
          error,
          fallback: 'Hook 配置保存失败，请稍后重试。',
        );
        notifyListeners();
        return false;
      }
    });
  }

  Future<void> _loadLocked() async {
    final hadTrustedSnapshot = _hasTrustedSnapshot;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _store.ensureTable();
      _setEntries(await _store.loadAll());
      _hasTrustedSnapshot = true;
    } catch (error, stack) {
      silentLog('hooks_controller', '加载 Hook 配置', error, stack);
      _hasTrustedSnapshot = hadTrustedSnapshot;
      _errorMessage = userFailureMessage(error, fallback: 'Hook 配置加载失败，请稍后重试。');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureTrustedSnapshotLocked() async {
    if (_hasTrustedSnapshot) return true;
    await _loadLocked();
    return _hasTrustedSnapshot;
  }
}
