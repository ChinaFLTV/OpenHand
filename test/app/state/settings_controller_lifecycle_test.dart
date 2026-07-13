import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhand/app/model/app_settings_snapshot.dart';
import 'package:openhand/app/state/settings_controller.dart';
import 'package:openhand/app/state/settings_store.dart';

void main() {
  test('an in-flight save can finish after controller disposal', () async {
    final store = _DelayedSettingsStore();
    final controller = await SettingsController.create(store: store);
    final update = controller.updateThemeMode(ThemeMode.dark);
    await store.saveStarted.future;

    controller.dispose();
    store.releaseSave();

    expect(await update, isTrue);
    expect(store.saveCount, 1);
  });

  test('queued mutations do not run after controller disposal', () async {
    final store = _DelayedSettingsStore();
    final controller = await SettingsController.create(store: store);
    final first = controller.updateThemeMode(ThemeMode.dark);
    await store.saveStarted.future;
    final queued = controller.updateThemeMode(ThemeMode.light);

    controller.dispose();
    store.releaseSave();

    expect(await first, isTrue);
    expect(await queued, isFalse);
    expect(store.saveCount, 1);
  });

  test('mutations requested after disposal fail without saving', () async {
    final store = _DelayedSettingsStore(blockSaves: false);
    final controller = await SettingsController.create(store: store);
    controller.dispose();

    expect(await controller.updateThemeMode(ThemeMode.dark), isFalse);
    expect(store.saveCount, 0);
  });

  test('dispose is idempotent', () async {
    final controller = await SettingsController.create(
      store: _DelayedSettingsStore(blockSaves: false),
    );

    controller.dispose();

    expect(controller.dispose, returnsNormally);
  });
}

class _DelayedSettingsStore extends SettingsStore {
  _DelayedSettingsStore({this.blockSaves = true});

  final bool blockSaves;
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> _saveBarrier = Completer<void>();
  int saveCount = 0;

  @override
  String get settingsFilePath => 'memory://settings';

  @override
  Future<SettingsLoadResult> load() async {
    return SettingsLoadResult(snapshot: AppSettingsSnapshot.defaults());
  }

  @override
  Future<void> save(AppSettingsSnapshot snapshot) async {
    saveCount += 1;
    if (!saveStarted.isCompleted) saveStarted.complete();
    if (blockSaves) await _saveBarrier.future;
  }

  void releaseSave() {
    if (!_saveBarrier.isCompleted) _saveBarrier.complete();
  }
}
