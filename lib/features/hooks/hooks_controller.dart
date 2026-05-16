import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../app/model/hook_config.dart';
import 'data/hooks_store.dart';

/// Controller for managing hook configurations.
///
/// Follows the same ChangeNotifier + mutation queue pattern used by
/// SettingsController, McpController, etc.
class HooksController extends ChangeNotifier {
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
  bool _isDisposed = false;
  Future<void> _mutationQueue = Future<void>.value();

  List<HookEntry> get entries => _entriesView;

  /// Returns all enabled hooks for a specific event.
  List<HookEntry> enabledHooksForEvent(HookEvent event) {
    return _entries
        .where(
          (entry) => entry.event == event && entry.enabled && entry.hasScript,
        )
        .toList(growable: false);
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
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
    final entries = await _store.loadAll();
    _setEntries(entries);
    notifyListeners();
  }

  void _setEntries(List<HookEntry> entries) {
    _entries = entries;
    _entriesView = List<HookEntry>.unmodifiable(entries);
  }

  Future<bool> _commitMutation(Future<bool> Function() mutation) {
    final completer = Completer<bool>();
    _mutationQueue = _mutationQueue.then((_) async {
      try {
        final result = await mutation();
        notifyListeners();
        completer.complete(result);
      } catch (error) {
        completer.complete(false);
      }
    });
    return completer.future;
  }
}
