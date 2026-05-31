import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/hook_config.dart';
import '../../shared/core/managed_change_notifier.dart';
import 'data/hooks_store.dart';

/// Controller for managing hook configurations.
///
/// Follows the same ChangeNotifier + mutation queue pattern used by
/// SettingsController, McpController, etc.
class HooksController extends ManagedChangeNotifier {
  HooksController._({
    required HooksStore store,
    required List<HookEntry> entries,
  }) : _store = store,
       _entries = entries,
       _entriesView = List<HookEntry>.unmodifiable(entries);

  static const Uuid _uuid = Uuid();

  static Future<HooksController> create({HooksStore? store}) async {
    final effectiveStore = store ?? HooksStore();
    await effectiveStore.ensureTable();
    final entries = await effectiveStore.loadAll();
    return HooksController._(store: effectiveStore, entries: entries);
  }

  final HooksStore _store;
  List<HookEntry> _entries;
  List<HookEntry> _entriesView;
  final ChangePulse _saveSuccessPulse = ChangePulse();

  List<HookEntry> get entries => _entriesView;
  ValueListenable<int> get saveSuccessSignal => _saveSuccessPulse.listenable;

  /// Returns all enabled hooks for a specific event.
  List<HookEntry> enabledHooksForEvent(HookEvent event) {
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
      final newEntry = entry.copyWith(id: entry.id.isEmpty ? _uuid.v4() : null);
      _setEntries(<HookEntry>[..._entries, newEntry]);
      await _store.saveAll(_entries);
      return true;
    });
  }

  Future<bool> updateHook(HookEntry updated) async {
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == updated.id);
      if (index < 0) return false;
      _setEntries(<HookEntry>[
        ..._entries.sublist(0, index),
        updated,
        ..._entries.sublist(index + 1),
      ]);
      await _store.saveAll(_entries);
      return true;
    });
  }

  Future<bool> deleteHook(String id) async {
    return _commitMutation(() async {
      final before = _entries.length;
      _setEntries(_entries.where((item) => item.id != id).toList());
      if (_entries.length == before) return false;
      await _store.saveAll(_entries);
      return true;
    });
  }

  Future<bool> toggleHookEnabled(String id, {required bool enabled}) async {
    return _commitMutation(() async {
      final index = _entries.indexWhere((item) => item.id == id);
      if (index < 0) return false;
      _setEntries(<HookEntry>[
        ..._entries.sublist(0, index),
        _entries[index].copyWith(enabled: enabled),
        ..._entries.sublist(index + 1),
      ]);
      await _store.saveAll(_entries);
      return true;
    });
  }

  Future<void> refresh() async {
    await enqueueOperation(() async {
      final entries = await _store.loadAll();
      _setEntries(entries);
      notifyListeners();
    });
  }

  /// 删除所有 hook 条目（数据清理面板使用）。批处理走单次 saveAll([])。
  Future<bool> clearAll() async {
    return _commitMutation(() async {
      if (_entries.isEmpty) return true;
      _setEntries(const <HookEntry>[]);
      await _store.saveAll(const <HookEntry>[]);
      return true;
    });
  }

  void _setEntries(List<HookEntry> entries) {
    _entries = entries;
    _entriesView = List<HookEntry>.unmodifiable(entries);
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    return enqueueOperation(() async {
      final previousEntries = List<HookEntry>.from(_entries);
      try {
        final result = await mutation();
        if (result) {
          _saveSuccessPulse.emit();
        }
        notifyListeners();
        return result;
      } catch (_) {
        _setEntries(previousEntries);
        notifyListeners();
        return false;
      }
    });
  }
}
